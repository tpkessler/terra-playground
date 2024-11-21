-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileContributor: Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concept = require("concept")

local struct Stack(concept.Base) {}
local Integral = concept.Integral
local Any  = concept.Any

Stack.methods.size = {&Stack} -> Integral
Stack.methods.get = {&Stack, Integral} -> Any
Stack.methods.set = {&Stack, Integral, Any} -> {}

return {
    Stack = Stack,
}
