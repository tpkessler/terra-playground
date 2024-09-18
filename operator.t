-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concept = require("concept")
local vecbase = require("vector")

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
