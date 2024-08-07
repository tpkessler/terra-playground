local concept = require("concept")
local vecbase = require("vector_base")

local Bool = concept.Bool
local UInteger = concept.UInteger
local Number = concept.Number
local Vector = vecbase.Vector

local Operator = concept.AbstractInterface:new("Operator")
Operator:addmethod{
    rows = {} -> UInteger,
    cols = {} -> UInteger,
    apply = {Bool, Number, &Vector, Number, &Vector} -> {},
}

return {
    Operator = Operator,
}
