-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concepts = require("concepts")
local vecbase = require("vector")

local Bool = concepts.Bool
local Integral = concepts.Integral
local Number = concepts.Number
local Vector = vecbase.Vector

local struct Operator(concepts.Base) {}
Operator.methods.rows = {&Operator} -> Integral
Operator.methods.cols = {&Operator} -> Integral
Operator.methods.apply = {&Operator, Bool, Number, &Vector, Number, &Vector} -> {}

return {
    Operator = Operator,
}
