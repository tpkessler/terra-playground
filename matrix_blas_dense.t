local matrix = require("matrix")
local concept = require("concept")
local blas = require("blas")
local vecblas = require("vector_blas")
local err = require("assert")

local BLASVector = vecblas.VectorBLAS
local BLASNumber = concept.BLASNumber
local Bool = concept.Bool
local UInteger = concept.UInteger

local BLASDenseMatrix = concept.AbstractInterface:new("BLASDenseMatrix")
BLASDenseMatrix:inheritfrom(matrix.Matrix)
BLASDenseMatrix:addmethod{
    getblasdenseinfo = {} -> {UInteger, UInteger, &BLASNumber, UInteger},
}

local function BLASDenseMatrixBase(M)
    M.templates.apply[{&M.Self, Bool, BLASNumber, &BLASVector, BLASNumber, &BLASVector} -> {}]
    = function(Self, B, T1, V1, T2, V2)
        assert(Self.type.eltype == V1.type.eltype)
        assert(Self.type.eltype == V2.type.eltype)
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
                flag = blas.Trans
            else
                flag = blas.NoTrans
            end
            blas.gemv(blas.RowMajor, flag,
                      rows, cols, alpha, aptr, ld, xptr, incx,
                      beta, yptr, incy)
        end
        return apply
    end
end

return {
    BLASDenseMatrix = BLASDenseMatrix,
    BLASDenseMatrixBase = BLASDenseMatrixBase,
}
