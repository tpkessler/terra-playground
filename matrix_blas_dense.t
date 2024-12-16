-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local matrix = require("matrix")
local concepts = require("concepts")
local blas = require("blas")
local vecblas = require("vector_blas")
local err = require("assert")


local BLASReal = concepts.BLASReal
local BLASComplex = concepts.BLASComplex
local BLASNumber = concepts.BLASNumber
local BLASVector = concepts.BLASVector
local BLASMatrix = concepts.BLASDenseMatrix
local Transpose = concepts.Transpose

--[[

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
local terraform gemv(alpha : T, A : &M, x : &V1, beta : T, y : &V2) 
        where {T : BLASNumber, M : BLASMatrix(BLASNumber),  V1 : BLASVector(BLASNumber), V2 : BLASVector(BLASNumber)}
    var xptr, incx, yptr, incy, rows, cols, aptr, ld = gemvsetup(self, x, y)
    blas.gemv(blas.RowMajor, blas.NoTrans, rows, cols, alpha, aptr, ld, xptr, incx, beta, yptr, incy)
end

terraform gemv(alpha : T, A : &M, x : &V1, beta : T, y : &V2) 
        where {T : BLASReal, M : Transpose(BLASMatrix(BLASReal)),  V1 : BLASVector(BLASReal), V2 : BLASVector(BLASReal)}
    var xptr, incx, yptr, incy, rows, cols, aptr, ld = gemvsetup(self, x, y)
    blas.gemv(blas.RowMajor, blas.Trans, rows, cols, alpha, aptr, ld, xptr, incx, beta, yptr, incy)
end

terraform gemv(alpha : T, A : &M, x : &V1, beta : T, y : &V2) 
        where {T : BLASNumber, M : Transpose(BLASMatrix(BLASComplex)),  V1 : BLASVector(BLASComplex), V2 : BLASVector(BLASComplex)}
    var xptr, incx, yptr, incy, rows, cols, aptr, ld = gemvsetup(self, x, y)
    blas.gemv(blas.RowMajor, blas.ConjTrans, rows, cols, alpha, aptr, ld, xptr, incx, beta, yptr, incy)
end

local gemmsetup = macro(function(A, B, C)
    local T = C.type.type.eltype
    assert(T == A.type.type.eltype)
    assert(T == B.type.type.eltype)
    return quote
        var na, ma, ptra, lda = A:getblasdenseinfo()
        var nb, mb, ptrb, ldb = B:getblasdenseinfo()
        var nc, mc, ptrc, ldc = C:getblasdenseinfo()
        err.assert(nc == na)
        err.assert(mc == mb)
        err.assert(ma == nb)
        var m : uint64 = nc
        var n : uint64 = mc
        var k : uint64 = ma
    in
        n, m, k, ptra, lda, ptrb, ldb, ptrc, ldc
    end
end)

--C[i,j] = alpha * A[i,k] * B[k,j] + beta * C[i,j]
local terraform gemm(alpha : T, A : &M1, B : &M2, beta : T, C : &M3)
        where {T : BLASNumber, M1 : BLASMatrix(BLASNumber), M2 : BLASMatrix(BLASNumber), M3 : BLASMatrix(BLASNumber)}
    var n, m, k, ptra, lda, ptrb, ldb, ptrc, ldc = gemmsetup(A, B, C)
    blas.gemm(blas.RowMajor, blas.NoTrans, blas.NoTrans, 
        n, m, k, alpha, ptra, lda, ptrb, ldb, beta, ptrc, ldc)
end

--C[i,j] = alpha * A[i,k] * B[k,j] + beta * C[i,j]
local terraform gemm(alpha : T, A : &M1, B : &M2, beta : T, C : &M3)
        where {T : BLASNumber, M1 : Transpose(BLASMatrix(BLASNumber)), M2 : BLASMatrix(BLASNumber), M3 : BLASMatrix(BLASNumber)}
    var n, m, k, ptra, lda, ptrb, ldb, ptrc, ldc = gemmsetup(A, B, C)
    blas.gemm(blas.RowMajor, blas.Trans, blas.NoTrans, 
        n, m, k, alpha, ptra, lda, ptrb, ldb, beta, ptrc, ldc)
end

--C[i,j] = alpha * A[i,k] * B[k,j] + beta * C[i,j]
local terraform gemm(alpha : T, A : &M1, B : &M2, beta : T, C : &M3)
        where {T : BLASNumber, M1 : BLASMatrix(BLASNumber), M2 : BLASMatrix(BLASNumber), M3 : BLASMatrix(BLASNumber)}
    var n, m, k, ptra, lda, ptrb, ldb, ptrc, ldc = gemmsetup(A, B, C)
    blas.gemm(blas.RowMajor, blas.NoTrans, blas.NoTrans, 
        n, m, k, alpha, ptra, lda, ptrb, ldb, beta, ptrc, ldc)
end



return {
    BLASDenseMatrixBase = BLASDenseMatrixBase
}

--]]