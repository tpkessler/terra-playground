-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local compile = require("compile")
local boltzmann = require("boltzmann")

local GenerateBCWrapper = boltzmann.GenerateBCWrapper
local FixedPressure = boltzmann.FixedPressure

local pressurebc = GenerateBCWrapper(FixedPressure(double))
compile.generateCAPI("nonlinearbc", {pressurebc = pressurebc})
