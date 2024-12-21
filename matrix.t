-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local io = terralib.includec("stdio.h")
local concepts = require("concepts")
local blas = require("blas")
local err = require("assert")
local vecblas = require("vector_blas")

local Integer = concepts.Integer
local Number = concepts.Number
local Stack = concepts.Stack
local Matrix = concepts.Matrix

local BLASFloat = concepts.BLASFloat
local BLASComplexFloat = concepts.ComplexOverField(BLASFloat)
local BLASNumber = concepts.BLASNumber
local BLASVector = concepts.BLASVector
local BLASMatrix = concepts.BLASMatrix
local Transpose = concepts.Transpose

--[[
--C[i,j] = alpha * A[i,k] * B[k,j] + beta * C[i,j]
local terraform gemm(alpha : T, A : &M1, B : &M2, beta : T, C : &M3)
        where {T : Number, M1 : Matrix(Number), M2 : Matrix(Number), M3 : Matrix(Number)}
    err.assert(A:size(1) == B:size(0), "ArgumentError: matrix dimensions in C = alpha*C + beta * A * B are not consistent.")
    err.assert(C:size(0) == A:size(0) and C:size(1) == B:size(1), "ArgumentError: matrix dimensions in C = alpha*C + beta * A * B are not consistent.")
    for i = 0, C:size(0) do
        for j = 0, C:size(1) do
            var sum = beta * C:get(i, j)
            for k = 0, A:size(1) do
                sum = sum + alpha * A:get(i, k) * B:get(k, j)
            end
            C:set(i, j, sum)
        end
    end
end
--]]

--compute y[i] = alpha * A[i,j] * x[j] + beta * y[i]
local terraform gemv(alpha : T, A : &M, x : &V1, beta : T, y : &V2) 
        where {T : Number, M : Matrix(Number),  V1 : Stack(Number), V2 : Stack(Number)}
    io.printf("gemv fallback - %s\n", [tostring(T)])
    var ns = A:size(0)
    var ms = A:size(1)
    var nx = x:length()
    var ny = y:length()
    err.assert(ns == ny and ms == nx)
    for i = 0, ns do
        var res = T(0)
        for j = 0, ms do
            res = res + A:get(i, j) * x:get(j)
        end
        y:set(i, beta * y:get(i) + alpha * res)
    end
end

local gemvsetup = macro(function(self, x, y)
    return quote
        var nx, xptr, incx = x:getblasinfo()
        var ny, yptr, incy = y:getblasinfo()
        var rows, cols, aptr, ld = self:getblasdenseinfo()
        err.assert(rows == ny and cols == nx)
    in
        xptr, incx, yptr, incy, rows, cols, aptr, ld
    end
end)

--compute y[i] = alpha * A[i,j] * x[j] + beta * y[i]
terraform gemv(alpha : T, A : &M, x : &V1, beta : T, y : &V2) 
        where {T : BLASNumber, M : BLASMatrix(BLASNumber),  V1 : BLASVector(BLASNumber), V2 : BLASVector(BLASNumber)}
    var xptr, incx, yptr, incy, rows, cols, aptr, ld = gemvsetup(A, x, y)
    blas.gemv(blas.RowMajor, blas.NoTrans, rows, cols, alpha, aptr, ld, xptr, incx, beta, yptr, incy)
end

local BLASMatrixReal = BLASMatrix(BLASFloat)

terraform gemv(alpha : T, A : &M, x : &V1, beta : T, y : &V2) 
        where {T : BLASFloat, M : Transpose(BLASMatrixReal),  V1 : BLASVector(BLASFloat), V2 : BLASVector(BLASFloat)}
    var xptr, incx, yptr, incy, rows, cols, aptr, ld = gemvsetup(A, x, y)
    blas.gemv(blas.RowMajor, blas.Trans, cols, rows, alpha, aptr, ld, xptr, incx, beta, yptr, incy)
end

local BLASMatrixComplex = BLASMatrix(BLASComplexFloat)

terraform gemv(alpha : T, A : &M, x : &V1, beta : T, y : &V2) 
        where {T : BLASComplexFloat, M : Transpose(BLASMatrixComplex),  V1 : BLASVector(BLASComplexFloat), V2 : BLASVector(BLASComplexFloat)}
    var xptr, incx, yptr, incy, rows, cols, aptr, ld = gemvsetup(A, x, y)
    blas.gemv(blas.RowMajor, blas.ConjTrans, cols, rows, alpha, aptr, ld, xptr, incx, beta, yptr, incy)
end

return {
    gemv = gemv,
    --gemm = gemm
}
