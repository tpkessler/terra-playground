-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local factorization = require("factorization")
local base = require("base")
local err = require("assert")
local concept = require("concept")
local template = require("template")
local matbase = require("matrix")
local vecbase = require("vector")
local veccont = require("vector_contiguous")
local matblas = require("matrix_blas_dense")
local vecblas = require("vector_blas")
local mathfun = require("mathfuns")
local lapack = require("lapack")

local factorize = template.Template:new("factorize")

local Matrix = matbase.Matrix
local Vector = vecbase.Vector
local Number = concept.Number
factorize[{&Matrix, &Vector, Number} -> {}] = function(M, P, T)
    assert(concept.Integral(P.type.eltype), "Permutation array doesn't have integral type")
    local terra factorize(a: M, p: P, tol: T)
        var n = a:rows()
        for i = 0, n do
            p:set(i, i)
        end
        for i = 0, n do
            var maxA = [T](0)
            var imax = i
            for k = i, n do
                var absA = mathfun.abs(a:get(k, i))
                if absA > maxA then
                    maxA = absA
                    imax = k
                end
            end

            err.assert(maxA > tol)

            if imax ~= i then
                var j = p:get(i)
                p:set(i, p:get(imax))
                p:set(imax, j)

                for k = 0, n do
                    var tmp = a:get(i, k)
                    a:set(i, k, a:get(imax, k))
                    a:set(imax, k, tmp)
                end
            end

            for j = i + 1, n do
                a:set(j, i, a:get(j, i) / a:get(i, i))

                for k = i + 1, n do
                    var tmp = a:get(j, k)
                    a:set(j, k, tmp - a:get(j, i) * a:get(i, k))
                end
            end
        end
    end
    return factorize
end

local MatBLAS = matblas.BLASDenseMatrix
local VectorContiguous = veccont.VectorContiguous
factorize[{&MatBLAS, &VectorContiguous, Number} -> {}] = function(M, P, T)
    assert(P.type.eltype == int32, "Only 32 bit LAPACK interface supported")
    local terra factorize(a: M, p: P, tol: T)
        var n, m, adata, lda = a:getblasdenseinfo()
        err.assert(n == m)
        var np, pdata = p:getbuffer()
        err.assert(n == np)
        lapack.getrf(lapack.ROW_MAJOR, n, n, adata, lda, pdata)
    end

    return factorize
end

local Bool = concept.Bool
local solve = template.Template:new("solve")
solve[{Bool, &Matrix, &Vector, &Vector} -> {}] = function(B, M, P, V)
    assert(concept.Integral(P.type.eltype), "Permutation array doesn't have integral type")
    local conj = mathfun.conj
    local terra solve(trans: B, a: M, p: P, x: V)
        var n = a:rows()
        if not trans then
            for i = 0, n do
                var idx = p:get(i)
                while idx < i do
                    idx = p:get(idx)
                end
                var tmp = x:get(i)
                x:set(i, x:get(idx))
                x:set(idx, tmp)
            end

            for i = 0, n do
                for k = 0, i do
                    x:set(i, x:get(i) - a:get(i, k) * x:get(k))
                end
            end

            for ii = 0, n do
                var i = n - 1 - ii
                for k = i + 1, n do
                    x:set(i, x:get(i) - a:get(i, k) * x:get(k))
                end
                x:set(i, x:get(i) / a:get(i, i))
            end
        else
            for i = 0, n do
                for k = 0, i do
                    x:set(i, x:get(i) - conj(a:get(k, i)) * x:get(k))
                end
                x:set(i, x:get(i) / conj(a:get(i, i)))
            end

            for ii = 0, n do
                var i = n - 1 - ii
                for k = i + 1, n do
                    x:set(i, x:get(i) - conj(a:get(k, i)) * x:get(k))
                end
            end

            for ii = 0, n do
                var i = n - 1 - ii
                var idx = p:get(i)
                while idx < i do
                    idx = p:get(idx)
                end
                var tmp = x:get(i)
                x:set(i, x:get(idx))
                x:set(idx, tmp)
            end
        end
    end
    return solve
end

local function get_trans(T)
    if concept.Complex(T) then
        return "C"
    else
        return "T"
    end
end

local VectorBLAS = vecblas.VectorBLAS
solve[{Bool, &MatBLAS, &VectorContiguous, &VectorBLAS} -> {}] = function(B, M, P, V)
    assert(P.type.eltype == int32, "Only 32 bit LAPACK interface supported")
    local terra solve(trans: B, a: M, p: P, x: V)
        var n, m, adata, lda = a:getblasdenseinfo()
        err.assert(n == m)
        var np, pdata = p:getbuffer()
        err.assert(n == np)
        var nx, xdata, incx = x:getblasinfo()
        var lapack_trans: rawstring
        if trans then
            lapack_trans = [get_trans(M.type.eltype)]
        else
            lapack_trans = "N"
        end
        lapack.getrs(lapack.ROW_MAJOR, @lapack_trans, n, 1, adata, lda, pdata, xdata, incx)
    end

    return solve
end

local LUFactory = terralib.memoize(function(M, P)
    assert(matbase.Matrix(M), "Type " .. tostring(M)
                              .. " does not implement the matrix interface")
    assert(vecbase.Vector(P), "Type " .. tostring(P)
                              .. " does not implement the vector interface")
    assert(concept.Integral(P.eltype), "Permutation vector has to be of integer type")

    local T = M.eltype
    local Ts = T
    local Ts = concept.Complex(T) and T.eltype or T
    local struct lu{
        a: &M
        p: &P
        tol: Ts
    }
    function lu.metamethods.__typename(self)
        return ("LUFactorization(%s)"):format(tostring(T))
    end
    base.AbstractBase(lu)

    terra lu:rows()
        return self.a:rows()
    end

    terra lu:cols()
        return self.a:cols()
    end

    local factorize = factorize(&M, &P, Ts)
    terra lu:factorize()
        factorize(self.a, self.p, self.tol)
    end

    lu.templates.solve = template.Template:new("solve")
    lu.templates.solve[{&lu.Self, Bool, &Vector} -> {}] = function(Self, B, V)
        local impl = solve(B, &M, &P, V)
        local terra solve(self: Self, trans: B, x: V)
            impl(trans, self.a, self.p, x)
        end
        return solve
    end

    local Number = concept.Number
    lu.templates.apply = template.Template:new("apply")
    lu.templates.apply[{&lu.Self, Bool, Number, &Vector, Number, &Vector} -> {}]
    = function(Self, B, T1, V1, T2, V2)
        local terra apply(self: Self, trans: B, a: T1, x: V1, b: T2, y: V2)
            self:solve(trans, x)
            y:scal(b)
            y:axpy(a, x)
        end
        return apply
    end

    assert(factorization.Factorization(lu))
    factorization.Factorization:addimplementations{lu}

    lu.staticmethods.new = terra(a: &M, p: &P, tol: Ts)
        err.assert(a:rows() == a:cols())
        err.assert(p:size() == a:rows())
        return lu {a, p, tol}
    end

    return lu
end)

return {
    LUFactory = LUFactory,
}
