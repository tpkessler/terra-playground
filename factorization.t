local concept = require("concept")
local vecbase = require("vector")
local operator = require("operator")

local Bool = concept.Bool
local Vector = vecbase.Vector
local Factorization = concept.AbstractInterface:new("Factorization")
Factorization:inheritfrom(operator.Operator)
Factorization:addmethod{
    factorize = {} -> {},
    solve = {Bool, &Vector} -> {},
}

return {
    Factorization = Factorization
}
