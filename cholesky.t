-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"

local factorization = require("factorization")
local base = require("base")
local err = require("assert")
local concept = require("concept")
local matbase = require("matrix")
local vecbase = require("vector")
local veccont = require("vector_contiguous")
local matblas = require("matrix_blas_dense")
local vecblas = require("vector_blas")
local mathfun = require("mathfuns")
local lapack = require("lapack")

local Matrix = matbase.Matrix
local Number = concept.Number
terraform factorize(a: &M, tol: T) where {M: Matrix, T: Number}
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

local MatBLAS = matblas.BLASDenseMatrix
local BLASNumber = concept.BLASNumber
terraform factorize(a: &M, tol: T) where {M: MatBLAS, T: BLASNumber}
    var n, m, adata, lda = a:getblasdenseinfo()
    err.assert(n == m)
    lapack.potrf(lapack.ROW_MAJOR, @"L", n, adata, lda)
end

local Bool = concept.Bool
local Vector = vecbase.Vector
local conj = mathfun.conj
terraform solve(trans: B, a: &M, x: &V) where {B: Bool, M: Matrix, V: Vector}
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

local VectorBLAS = vecblas.VectorBLAS
terraform solve(trans: B, a: &M, x: &V)
    where {B: Bool, M: MatBLAS, V: VectorBLAS}
    var n, m, adata, lda = a:getblasdenseinfo()
    err.assert(n == m)
    var nx, xdata, incx = x:getblasinfo()
    lapack.potrs(lapack.ROW_MAJOR, @"L", n, 1, adata, lda, xdata, incx)
end

local CholeskyFactory = terralib.memoize(function(M)
    assert(matbase.Matrix(M), "Type " .. tostring(M)
                              .. " does not implement the matrix interface")
    local T = M.eltype
    local Ts = T
    local Ts = concept.Complex(T) and T.traits.eltype or T
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

    terra cho:factorize()
        escape
            local impl = factorize:dispatch(&M, Ts)
            emit quote return impl(self.a, self.tol) end
        end
    end

    terraform cho:solve(trans: bool, x: &V) where {V: Vector}
        return solve(trans, self.a, x)
    end

    terraform cho:apply(trans: B, a: T1, x: &V1, b: T2, y: &V2)
        where {B: Bool, T1: Number, V1: Vector, T2: Number, V2: Vector}
        self:solve(trans, x)
        y:scal(b)
        y:axpy(a, x)
    end

    assert(factorization.Factorization(cho))

    cho.staticmethods.new = terra(a: &M, tol: Ts)
        err.assert(a:rows() == a:cols())
        return cho {a, tol}
    end

    return cho
end)

return {
    CholeskyFactory = CholeskyFactory,
}
