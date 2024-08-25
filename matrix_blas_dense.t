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

    M.templates.apply[{&M.Self, Bool, BLASNumber, &BLASVector, BLASNumber, &BLASVector} -> {}]
    = function(Self, B, T1, V1, T2, V2)
        local T = Self.type.eltype
        assert(T == V1.type.eltype)
        assert(T == V2.type.eltype)
        local terra apply(self: Self, trans: B, alpha: T1, x: V1, beta: T2, y: V2)
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
        return apply
    end

    M.templates.mul[{&M.Self, BLASNumber, BLASNumber, Bool, &BLASDenseMatrix,
                     Bool, &BLASDenseMatrix} -> {}]
    = function(Self, S1, S2, B1, M1, B2, M2)
        local T = Self.type.eltype
        assert(T == M1.type.eltype)
        assert(T == M2.type.eltype)
        local terra mul(self: Self, beta: S1, alpha: S2, atrans: B1, a: M1,
                        btrans: B2, b: M2)
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
        return mul
    end
end

return {
    BLASDenseMatrix = BLASDenseMatrix,
    BLASDenseMatrixBase = BLASDenseMatrixBase,
}
