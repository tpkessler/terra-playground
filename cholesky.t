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

local io = terralib.includec("stdio.h")

local Matrix = matbase.Matrix
local Number = concept.Number
factorize[{&Matrix, Number} -> {}] = function(M, T)
    local terra factorize(a: M, tol: T)
        var n = a:rows()
        for i = 0, n do
            for j = 0, i + 1 do
                var sum = a:get(i, j)
                for k = 0, j do
                    sum = sum - a:get(i, k) * mathfun.conj(a:get(j, k))
                end
                if i == j then
                    var sumabs = mathfun.abs(sum)
                    err.assert(mathfun.abs(sum - sumabs) < tol * sumabs + tol)
                    a:set(i, i, mathfun.sqrt(sumabs))
                else
                    a:set(i, j, sum / a:get(j, j))
                end
            end
        end
    end
    return factorize
end

local MatBLAS = matblas.BLASDenseMatrix
local VectorContiguous = veccont.VectorContiguous
factorize[{&MatBLAS, &VectorContiguous, Number} -> {}] = function(M, T)
    local terra factorize(a: M, tol: T)
        var n, m, adata, lda = a:getblasdenseinfo()
        err.assert(n == m)
        lapack.potrf(lapack.ROW_MAJOR, @"L", n, adata, lda)
    end

    return factorize
end

local Bool = concept.Bool
local Vector = vecbase.Vector
local solve = template.Template:new("solve")
solve[{Bool, &Matrix, &Vector} -> {}] = function(B, M, V)
    local conj = mathfun.conj
    local terra solve(trans: B, a: M, x: V)
        var n = a:rows()
        for i = 0, n do
            for k = 0, i do
                x:set(i, x:get(i) - a:get(i, k) * x:get(k))
            end
            x:set(i, x:get(i) / a:get(i, i))
        end

        for ii = 0, n do
            var i = n - 1 - ii
            for k = i + 1, n do
                x:set(i, x:get(i) - mathfun.conj(a:get(k, i)) * x:get(k))
            end
            x:set(i, x:get(i) / a:get(i, i))
        end
    end
    return solve
end

local VectorBLAS = vecblas.VectorBLAS
solve[{Bool, &MatBLAS, &VectorBLAS} -> {}] = function(B, M, V)
    local terra solve(trans: B, a: M, x: V)
        var n, m, adata, lda = a:getblasdenseinfo()
        err.assert(n == m)
        var nx, xdata, incx = x:getblasinfo()
        lapack.potrs(lapack.ROW_MAJOR, @"L", n, 1, adata, lda, xdata, incx)
    end

    return solve
end

local CholeskyFactory = terralib.memoize(function(M)
    assert(matbase.Matrix(M), "Type " .. tostring(M)
                              .. " does not implement the matrix interface")
    local T = M.eltype
    local Ts = T
    local Ts = concept.Complex(T) and T.eltype or T
    local struct cho{
        a: &M
        tol: Ts
    }
    function cho.metamethods.__typename(self)
        return ("CholeskyFactorization(%s)"):format(tostring(T))
    end
    base.AbstractBase(cho)

    terra cho:rows()
        return self.a:rows()
    end

    terra cho:cols()
        return self.a:cols()
    end

    local factorize = factorize(&M, Ts)
    terra cho:factorize()
        factorize(self.a, self.tol)
    end

    cho.templates.solve = template.Template:new("solve")
    cho.templates.solve[{&cho.Self, Bool, &Vector} -> {}] = function(Self, B, V)
        local impl = solve(B, &M, V)
        local terra solve(self: Self, trans: B, x: V)
            impl(trans, self.a, x)
        end
        return solve
    end

    local Number = concept.Number
    cho.templates.apply = template.Template:new("apply")
    cho.templates.apply[{&cho.Self, Bool, Number, &Vector, Number, &Vector} -> {}]
    = function(Self, B, T1, V1, T2, V2)
        local terra apply(self: Self, trans: B, a: T1, x: V1, b: T2, y: V2)
            self:solve(trans, x)
            y:scal(b)
            y:axpy(a, x)
        end
        return apply
    end

    assert(factorization.Factorization(cho))
    factorization.Factorization:addimplementations{cho}

    cho.staticmethods.new = terra(a: &M, tol: Ts)
        err.assert(a:rows() == a:cols())
        return cho {a, tol}
    end

    return cho
end)

return {
    CholeskyFactory = CholeskyFactory,
}
