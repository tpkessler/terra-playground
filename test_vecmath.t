-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local vecmath = require("vecmath")
local tmath = require("tmath")

import "terratest/terratest"

local intrinsic = {}
intrinsic.AVX = 1
if vecmath.has_avx512_support() then
    intrinsic.AVX512 = 2
end

for _, T in pairs{float, double} do
    for cpuset, factor in pairs(intrinsic) do
        local width = factor * 32 / sizeof(T)
        local arg = {}
        for i = 1, width do
            arg[i] = 0.1 * i
        end
        for _, name in pairs{"sin", "cos", "exp", "log", "sqrt"} do
            testenv(T, cpuset, name) "Math function" do
                local vecfunc = vecmath[tostring(T)][width][name]
                local reffunc = tmath[name]
                terracode
                    var x = vectorof(T, [arg])
                    var yvec = vecfunc(x)
                    var yref: T[width]
                    for i = 0, width do
                        yref[i] = reffunc(x[i])
                    end
                end
                for i = 0, width - 1 do
                    test tmath.isapprox(yref[i], yvec[i], [T](1e-6))
                end
            end
        end
    end
end
