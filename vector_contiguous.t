-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

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
