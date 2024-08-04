local matrix = require("matrix")
local concept = require("concept")

local BLASNumber = concept.BLASNumber
local UInteger = concept.UInteger

local BLASDenseMatrix = concept.AbstractInterface:new("BLASDenseMatrix")
BLASDenseMatrix:inheritfrom(matrix.Matrix)
BLASDenseMatrix:addmethod{
    getblasdenseinfo = {} -> {UInteger, UInteger, &BLASNumber, UInteger},
}

local function BLASDenseMatrixBase(M)

end

return {
    BLASDenseMatrix = BLASDenseMatrix,
    BLASDenseMatrixBase = BLASDenseMatrixBase,
}
