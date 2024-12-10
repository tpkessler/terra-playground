
--[[
local DynamicVector = function(T)

    --generate the raw type
    local DVector = DArrayRawType(T, 1)
    
    function DVector.metamethods.__typename(self)
        return ("DynamicVector(%s)"):format(tostring(T))
    end
    
    --add base functionality
    base.AbstractBase(DVector)

    --implement interfaces
    DArrayStackBase(DVector)
    DArrayVectorBase(DVector)
    DArrayIteratorBase(DVector)

    veccont.VectorContiguous:addimplementations{DVector}

    if concepts.BLASNumber(T) then
        terra DVector:getblasinfo()
            return self:length(), self:getdataptr(), 1
        end
    end

    assert(vecbase.Vector(DVector))

    return DVector
end

local DynamicMatrix = function(T, options)
    
    local DMatrix = DArrayRawType(T, 2, options)

    --check that a matrix-type was generated
    assert(DMatrix.ndims == 2, "ArgumentError: expected an array of dimension 2.")

    function DMatrix.metamethods.__typename(self)
        local perm = "{"
        for i = 1, Array.ndims-1 do
            perm = perm .. tostring(Array.perm[i]) .. ","
        end
        perm = perm .. tostring(Array.perm[Array.ndims]) .. "}"
        return "DynamicMatrix(" .. tostring(T) ..", " .. tostring(Array.ndims) .. ", perm = " .. perm .. ")"
    end

    --add base functionality
    base.AbstractBase(DMatrix)

    --implement interfaces
    DArrayStackBase(DMatrix)
    DArrayVectorBase(DMatrix)
    DArrayIteratorBase(DMatrix)

    --add linear operator functionality
    matbase.MatrixBase(DMatrix)
    
    if concepts.BLASNumber(T) then
        terra DMatrix:getblasdenseinfo()
            return self:size(0), self:size(1), self:getdataptr(), self:size(1)
        end
        local matblas = require("matrix_blas_dense")
        matblas.BLASDenseMatrixBase(DMatrix)
    end

    assert(matbase.Matrix(DMatrix))

    return DMatrix
end
--]]