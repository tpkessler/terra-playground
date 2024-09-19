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
factorize[{&Matrix, &Vector} -> {}] = function(M, U)
    local T = M.type.eltype
    local terra factorize(a: M, u: U)
        var n = a:cols()
        for j = 0, n do
            -- Compute the norm of column j.
            -- First, we compute the square and then take the square root.
            var musqr = [T](0)
            for k = j, n do
                musqr = musqr + a:get(k, j) * mathfun.conj(a:get(k, j))
            end
            -- musqr is a real number but musqr is of type T which could be complex,
            -- so we take its real part before computing the square root.
            var mu = mathfun.sqrt(mathfun.real(musqr))
            -- Compute optimal phase to reduce round-off error
            var diag = mathfun.abs(a:get(j, j))
            var lambda = a:get(j, j) / diag
            -- With the optimal phase factor, the Householder reflection reads
            -- Id - 2 u u^H
            -- where u is the normalized difference of the j-th column vector
            -- and the scaled unit vector e_j of the same norm.
            -- The norm of the difference with the specific choice of lambda
            -- is given by beta,
            var beta = mathfun.sqrt(2 * mu * (mu + diag))
            -- We store the Householder vector in the j-th column of a and
            -- the diagonal entry a(j, j) in the vector u.
            a:set(j, j, lambda * (diag + mu) / beta)
            for k = j + 1, n do
                a:set(k, j, a:get(k, j) / beta)
            end
            u:set(j, -lambda * mu)
            -- Apply the Householder reflection to the remaining columns
            for l = j + 1, n do
                var dot = [T](0)
                for k = j, n do
                    dot = dot + mathfun.conj(a:get(k, j)) * a:get(k, l)
                end
                for k = j, n do
                    a:set(k, l, a:get(k, l) - 2 * dot * a:get(k, j))
                end
            end
        end
    end
    return factorize
end

local MatBLAS = matblas.BLASDenseMatrix
local VectorContiguous = veccont.VectorContiguous
factorize[{&MatBLAS, &VectorContiguous} -> {}] = function(M, U)
    local terra factorize(a: M, u: U)
        var n, m, adata, lda = a:getblasdenseinfo()
        err.assert(n == m)
        var nu, udata = u:getbuffer()
        err.assert(n == nu)
        lapack.geqrf(lapack.ROW_MAJOR, n, n, adata, lda, udata)
    end

    return factorize
end

local Bool = concept.Bool
local solve = template.Template:new("solve")
solve[{Bool, &Matrix, &Vector, &Vector} -> {}] = function(B, M, U, V)
    local T = M.type.eltype

    local terra householder(a: M, x: V, i: uint64)
        var n = a:rows()
        var dot = [T](0)
        for k = i, n do
            dot = dot + mathfun.conj(a:get(k, i)) * x:get(k)
        end
        for k = i, n do
            x:set(k, x:get(k) - 2 * dot * a:get(k, i))
        end
    end
    
    local terra solve(trans: B, a: M, u: U, x: V)
        var n = a:rows()
        if trans then
            for i = 0, n do
                for j = 0, i do
                    x:set(i, x:get(i) - mathfun.conj(a:get(j, i)) * x:get(j))
                end
                x:set(i, x:get(i) / mathfun.conj(u:get(i)))
            end
            
            for ii = 0, n do
                var i = n - 1 - ii
                householder(a, x, i)
            end
        else
            -- Householder reflections are self-adjoint, so when applying Q^H,
            -- only the ordering of the reflections changes.
            for i = 0, n do
                householder(a, x, i)
            end

            for ii = 0, n do
                var i = n - 1 - ii
                for j = i + 1, n do
                    x:set(i, x:get(i) - a:get(i, j) * x:get(j))
                end
                x:set(i, x:get(i) / u:get(i))
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
solve[{Bool, &MatBLAS, &VectorContiguous, &VectorBLAS} -> {}] = function(B, M, U, V)
    local terra solve(trans: B, a: M, u: U, x: V)
        var n, m, adata, lda = a:getblasdenseinfo()
        err.assert(n == m)
        var nu, udata = u:getbuffer()
        err.assert(n == nu)
        var nx, xdata, incx = x:getblasinfo()
        if trans then
            var lapack_trans = [get_trans(M.type.eltype)]
            lapack.trtrs(lapack.ROW_MAJOR, @"U", @lapack_trans, @"N", n, 1,
                         adata, lda, xdata, incx)
            lapack.ormqr(lapack.ROW_MAJOR, @"L", @"N", n, 1, n,
                         adata, lda, udata, xdata, incx)
        else
            var lapack_trans = [get_trans(M.type.eltype)]
            lapack.ormqr(lapack.ROW_MAJOR, @"L", @lapack_trans, n, 1, n,
                         adata, lda, udata, xdata, incx)
            lapack.trtrs(lapack.ROW_MAJOR, @"U", @"N", @"N", n, 1,
                         adata, lda, xdata, incx)
        end
    end

    return solve
end

local QRFactory = terralib.memoize(function(M, U)
    assert(matbase.Matrix(M), "Type " .. tostring(M)
                              .. " does not implement the matrix interface")
    assert(vecbase.Vector(U), "Type " .. tostring(U)
                              .. " does not implement the vector interface")

    local struct qr{
        a: &M
        u: &U
    }
    function qr.metamethods.__typename(self)
        return ("QRFactorization(%s, %s)"):format(tostring(M), tostring(U))
    end
    base.AbstractBase(qr)

    terra qr:rows()
        return self.a:rows()
    end

    terra qr:cols()
        return self.a:cols()
    end

    local factorize = factorize(&M, &U)
    terra qr:factorize()
        factorize(self.a, self.u)
    end

    qr.templates.solve = template.Template:new("solve")
    qr.templates.solve[{&qr.Self, Bool, &Vector} -> {}] = function(Self, B, V)
        local impl = solve(B, &M, &U, V)
        local terra solve(self: Self, trans: B, x: V)
            impl(trans, self.a, self.u, x)
        end
        return solve
    end

    local Number = concept.Number
    qr.templates.apply = template.Template:new("apply")
    qr.templates.apply[{&qr.Self, Bool, Number, &Vector, Number, &Vector} -> {}]
    = function(Self, B, T1, V1, T2, V2)
        local terra apply(self: Self, trans: B, a: T1, x: V1, b: T2, y: V2)
            self:solve(trans, x)
            y:scal(b)
            y:axpy(a, x)
        end
        return apply
    end

    assert(factorization.Factorization(qr))
    factorization.Factorization:addimplementations{qr}

    qr.staticmethods.new = terra(a: &M, u: &U)
        err.assert(a:rows() == a:cols())
        err.assert(u:size() == a:rows())
        return qr {a, u}
    end

    return qr
end)

return {
    QRFactory = QRFactory,
}
