local operator = require("operator")
local concept = require("concept")

local UInteger = concept.UInteger
local Number = concept.Number

local Matrix = concept.AbstractInterface:new("Matrix")
Matrix:inheritfrom(operator.Operator)
Matrix:addmethod{
    set = {UInteger, UInteger, Number} -> {},
    get = {UInteger, UInteger} -> {Number},
}

return {
    Matrix = Matrix,
}
