-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

local alloc = require("alloc")
local boltzmann = require("boltzmann")
local dual = require("dual")
local svector = require("svector")
local tmath = require("mathfuns")
local range = require("range")

for N = 2, 29 do
    testenv(N) "Half space integral aligned" do
        local Alloc = alloc.DefaultAllocator()
        local T = dual.DualNumber(double)
        local HalfSpace = boltzmann.HalfSpaceQuadrature(T)

        terracode
            var alloc: Alloc
            var rho = T {2.0 / 3.0, 3}
            var u = [svector.StaticVector(T, 3)].from(T {-1.5, -6.75}, 0, 0)
            var theta = T {(9 + 1.0 / 6.0) / 10.0, 6.75}
            var hs = HalfSpace.new(1, 0, 0)
            var xh, wh = hs:maxwellian(&alloc, N, rho, &u, theta)

        end

        testset "Integral with constant function" do
            terracode
                var res: T = 0
                for w in wh do
                    res = res + w
                end
                var ref = T {0.039061695732712676, 0.0758567169526779}
            end

            test tmath.isapprox(res.val, ref.val, 1e-12 * ref.val)
            test tmath.isapprox(res.tng, ref.tng, 1e-12 * ref.tng)
        end

        testset "Integral with linear function" do
            terracode
                var res: T = 0
                var q = range.zip(&xh, &wh)
                for xw in q do
                    var x, w = xw
                    res = res + x._0 * w
                end
                var ref = T {0.01603974390209162, 0.0832949144360567}
            end

            test tmath.isapprox(res.val, ref.val, 1e-12 * ref.val)
            test tmath.isapprox(res.tng, ref.tng, 1e-12 * ref.tng)
        end
    end

    testenv(N) "Half space integral rotated" do
        local Alloc = alloc.DefaultAllocator()
        local T = dual.DualNumber(double)
        local HalfSpace = boltzmann.HalfSpaceQuadrature(T)

        terracode
            var alloc: Alloc
            var rho = T {2.0 / 3.0, 3}
            var u = (
                    [svector.StaticVector(T, 3)]
                ).from(
                    T {1.5, -6.75},
                    T {0.2, 0.1},
                    T {1, 3}
                )
            var theta = T {(9 + 1.0 / 6.0) / 10.0, 6.75}
            var hs = HalfSpace.new(
                1 / tmath.sqrt(3.0), 1 / tmath.sqrt(3.0), 1 / tmath.sqrt(3.0)
            )
            var xh, wh = hs:maxwellian(&alloc, N, rho, &u, theta)

        end

        testset "Integral with constant function" do
            terracode
                var res: T = 0
                for w in wh do
                    res = res + w
                end
                var ref = T {0.6321697677872029, 2.2656508775565514}
            end

            test tmath.isapprox(res.val, ref.val, 1e-12 * ref.val)
            test tmath.isapprox(res.tng, ref.tng, 1e-12 * ref.tng)
        end

        testset "Integral with linear function" do
            local io = terralib.includec("stdio.h")
            terracode
                var res: T = 0
                var q = range.zip(&xh, &wh)
                for xw in q do
                    var x, w = xw
                    res = res + (x._0 + x._1 + x._2) * w
                end
                var ref = T {1.824036771647169, 6.332175378550762}
            end

            test tmath.isapprox(res.val, ref.val, 1e-12 * ref.val)
            test tmath.isapprox(res.tng, ref.tng, 1e-12 * ref.tng)
        end
    end
end
