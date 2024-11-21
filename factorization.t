-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concept = require("concept")
local vecbase = require("vector")
local operator = require("operator")

local Bool = concept.Bool
local Vector = vecbase.Vector
local struct Factorization(concept.Base) {}
Factorization:inherit(operator.Operator)
Factorization.methods.factorize = {&Factorization} -> {}
Factorization.methods.solve = {&Factorization, Bool, &Vector} -> {}

return {
    Factorization = Factorization
}
