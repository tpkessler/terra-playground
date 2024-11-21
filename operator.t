-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concept = require("concept")
local vecbase = require("vector")

local Bool = concept.Bool
local Integral = concept.Integral
local Number = concept.Number
local Vector = vecbase.Vector

local struct Operator(concept.Base) {}
Operator.methods.rows = {&Operator} -> Integral
Operator.methods.cols = {&Operator} -> Integral
Operator.methods.apply = {&Operator, Bool, Number, &Vector, Number, &Vector} -> {}

return {
    Operator = Operator,
}
