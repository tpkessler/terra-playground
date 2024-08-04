local matrix = require("matrix")
local concept = require("concept")

local Number = concept.Number
local UInteger = concept.UInteger

local BLASMatrix = concept.AbstractInterface:new("BLASMatrix")
BLASMatrix:inheritfrom(matrix.Matrix)
BLASMatrix:addmethod{
    blasinfo = {} -> {UInteger, UInteger, &Number, UInteger},
}

return {
    BLASMatrix = BLASMatrix,
}
