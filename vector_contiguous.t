-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concept = require("concept")
local stack = require("stack")
local vecbase = require("vector")

local struct VectorContiguous(concept.Base) {}
local Integral = concept.Integral
local Number = concept.Number
VectorContiguous:inherit(vecbase.Vector)
VectorContiguous.methods.getbuffer = {&VectorContiguous} -> {Integral, &Number}

return {
    VectorContiguous = VectorContiguous
}
