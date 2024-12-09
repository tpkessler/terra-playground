-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concepts = require("concepts")
local stack = require("stack")
local vecbase = require("vector")

local struct VectorContiguous(concepts.Base) {}
local Integral = concepts.Integral
local Number = concepts.Number
VectorContiguous:inherit(vecbase.Vector)
VectorContiguous.methods.getbuffer = {&VectorContiguous} -> {Integral, &Number}

return {
    VectorContiguous = VectorContiguous
}
