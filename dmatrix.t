local alloc = require("alloc")
local base = require("base")
local concept = require("concept")
local matrix = require("matrix")
local err = require("assert")
local nfloat = require("nfloat")

local Allocator = alloc.Allocator
local size_t = uint64

local DynamicMatrix = terralib.memoize(function(T)
    local S = alloc.SmartBlock(T)
    
    local struct M(base.AbstractBase){
        data: S
        rows: size_t
        cols: size_t
        ld: size_t
    }
    M.eltype = T

    terra M:rows()
        return self.rows
    end

    terra M:cols()
        return self.cols
    end

    terra M:get(i: size_t, j: size_t)
        err.assert(i < self:rows() and j < self:cols())
        return self.data:get(j + self.ld * i)
    end

    terra M:set(i: size_t, j: size_t, a: T)
        err.assert(i < self:rows() and j < self:cols())
        self.data:set(j + self.ld * i, a)
    end

    matrix.MatrixBase(M)

    if concept.BLASNumber(T) then
        terra M:getblasdenseinfo()
            return self:rows(), self:cols(), self.data.ptr, self.ld
        end
        local matblas = require("matrix_blas_dense")
        matblas.BLASDenseMatrixBase(M)
    end

    return M
end)

local bigfloat = nfloat.FixedFloat(64)
local dmatrix = DynamicMatrix(double)
