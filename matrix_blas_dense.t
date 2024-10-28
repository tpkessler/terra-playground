-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local matrix = require("matrix")
local concept = require("concept")
local blas = require("blas")
local vecblas = require("vector_blas")
local err = require("assert")

local BLASVector = vecblas.VectorBLAS
local BLASNumber = concept.BLASNumber
local Complex = concept.Complex
local Bool = concept.Bool
local UInteger = concept.UInteger

local BLASDenseMatrix = concept.AbstractInterface:new("BLASDenseMatrix")
BLASDenseMatrix:inheritfrom(matrix.Matrix)
BLASDenseMatrix:addmethod{
    getblasdenseinfo = {} -> {UInteger, UInteger, &BLASNumber, UInteger},
}

local function BLASDenseMatrixBase(M)
    assert(BLASDenseMatrix(M))

    local conjtrans = function(T)
        if Complex(T) then
            return `blas.ConjTrans
        else
            return `blas.Trans
        end
    end

    terraform M:apply(trans : bool, alpha : T1, x : &V1, beta : T2, y : &V2) 
            where {T1 : BLASNumber, V1 : BLASVector, T2 : BLASNumber, V2 : BLASVector}
        escape
            local T = M.eltype
            --assert(T == x.type.type.eltype)
            --assert(T == y.type.type.eltype)
        end
        var nx, xptr, incx = x:getblasinfo()
        var ny, yptr, incy = y:getblasinfo()
        var rows, cols, aptr, ld = self:getblasdenseinfo()
        if trans then
            err.assert(cols == ny and rows == nx)
        else
            err.assert(rows == ny and cols == nx)
        end
        var flag = 0
        if trans then
            flag = [conjtrans(T)]
        else
            flag = blas.NoTrans
        end
        blas.gemv(blas.RowMajor, flag,
                    rows, cols, alpha, aptr, ld, xptr, incx,
                    beta, yptr, incy)
    end

    terraform M:mul(beta : S1, alpha : S2, atrans : bool, a : &M1, btrans : bool, b : &M2) 
            where {S1 : BLASNumber, S2 : BLASNumber, M1 : BLASDenseMatrix, M2 : BLASDenseMatrix}
        escape
            local T = M.eltype
            assert(T == a.type.type.eltype)
            assert(T == b.type.type.eltype)
        end
        var nc, mc, ptrc, ldc = self:getblasdenseinfo()
        var na, ma, ptra, lda = a:getblasdenseinfo()
        var nb, mb, ptrb, ldb = b:getblasdenseinfo()
        var m: uint64, n: uint64, k: uint64

        if atrans and btrans then
            err.assert(nc == ma)
            err.assert(mc == nb)
            err.assert(na == mb)
            m = nc
            n = mc
            k = na
        elseif atrans and not btrans then
            err.assert(nc == ma)
            err.assert(mc == mb)
            err.assert(na == nb)
            m = nc
            n = mc
            k = na
        elseif not atrans and btrans then
            err.assert(nc == na)
            err.assert(mc == nb)
            err.assert(ma == nb)
            m = nc
            n = mc
            k = ma
        else
            err.assert(nc == na)
            err.assert(mc == mb)
            err.assert(ma == nb)
            m = nc
            n = mc
            k = ma
        end

        var fa = 0
        if atrans then
            fa = [conjtrans(T)]
        else
            fa = blas.NoTrans
        end

        var fb = 0
        if btrans then
            fb = [conjtrans(T)]
        else
            fb = blas.NoTrans
        end
        blas.gemm(blas.RowMajor, fa, fb, n, m, k,
                    alpha, ptra, lda, ptrb, ldb, beta, ptrc, ldc)
    end

end

return {
    BLASDenseMatrix = BLASDenseMatrix,
    BLASDenseMatrixBase = BLASDenseMatrixBase,
}
