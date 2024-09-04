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

local solve = template.Template:new("solve")
solve[{&Matrix, &Vector, &Vector} -> {}] = function(M, P, V)
    assert(concept.Integral(P.type.eltype), "Permutation array doesn't have integral type")
    local terra solve(a: M, p: P, x: V)
        var n = a:rows()
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
    end
    return solve
end

local VectorBLAS = vecblas.VectorBLAS
solve[{&MatBLAS, &VectorContiguous, &VectorBLAS} -> {}] = function(M, P, V)
    assert(P.type.eltype == int32, "Only 32 bit LAPACK interface supported")
    local terra solve(a: M, p: P, x: V)
        var n, m, adata, lda = a:getblasdenseinfo()
        err.assert(n == m)
        var np, pdata = p:getbuffer()
        err.assert(n == np)
        var nx, xdata, incx = x:getblasinfo()
        lapack.getrs(lapack.ROW_MAJOR, @"N", n, 1, adata, lda, pdata, xdata, incx)
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
    local lu = terralib.types.newstruct("LU" .. tostring(M))
    lu.entries:insert{field = "a", type = &M}
    lu.entries:insert{field = "p", type = &P}
    lu.entries:insert{field = "tol", type = Ts}
    lu:complete()
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
    lu.templates.solve[{&lu.Self, &Vector} -> {}] = function(Self, V)
        local impl = solve(&M, &P, V)
        local terra solve(self: Self, x: V)
            impl(self.a, self.p, x)
        end
        return solve
    end

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
