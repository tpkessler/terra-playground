-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local vecmath = require("vecmath")
local tmath = require("tmath")

import "terratest/terratest"

for _, T in pairs{float, double} do
    for K = 2, vecmath.MAX_POW2 do
        local N = math.pow(2, K)
        local arg = {}
        for i = 1, N do
            arg[i] = 0.01 * i
        end
        for _, name in pairs{"sin", "cos", "exp", "log", "sqrt", "abs"} do
            testenv(T, N, name) "Math function" do
                local vecfunc = vecmath[name]
                local reffunc = tmath[name]
                terracode
                    var x = vectorof(T, [arg])
                    var yvec = vecfunc(x)
                    var yref: T[N]
                    for i = 0, N do
                        yref[i] = reffunc(x[i])
                    end
                end
                for i = 0, N - 1 do
                    test tmath.isapprox(yref[i], yvec[i], [T](1e-6))
                end
            end
        end
    end
end
