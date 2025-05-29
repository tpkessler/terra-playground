-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local compile = require("compile")
local boltzmann = require("boltzmann")

local GenerateLinearBCWrapper = boltzmann.GenerateLinearBCWrapper
local GenerateNonLinearBCWrapper = boltzmann.GenerateNonLinearBCWrapper
local FixedPressure = boltzmann.FixedPressure
local FixedMassFlowRate = boltzmann.FixedMassFlowRate

local halfspace = GenerateLinearBCWrapper()
local pressurebc = GenerateNonLinearBCWrapper(FixedPressure(double))
local massflowbc = GenerateNonLinearBCWrapper(FixedMassFlowRate(double))
compile.generateCAPI(
    "nonlinearbc",
    {pressurebc = pressurebc, halfspace = halfspace, massflowbc = massflowbc}
)
