local concept = require("concept")
local vecbase = require("vector")

local VectorContiguous = concept.AbstractInterface:new("VectorContiguous")
VectorContiguous:inheritfrom(vecbase.Vector)
VectorContiguous:addmethod{
    getbuffer = {} -> {concept.UInteger, &concept.Number},
}

return {
    VectorContiguous = VectorContiguous
}
