-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local base = require("base")
local dual = require("dual")
local darray = require("darray")
local concepts = require("concepts")
local recdiff = require("recdiff")
local tmath = require("tmath")

import "terraform"
import "terratest@v1/terratest"

local tols = {
    [float] = `1e-6f,
    [double] = `1e-15,
}

for S, tol in pairs(tols) do
    for _, isdual in pairs{false, true} do
        local DefaultAlloc = alloc.DefaultAllocator()
        local T = (isdual and dual.DualNumber(S) or S)
        testenv(T) "Bessel functions" do
            local struct besselj {
                x: T
            }
            function besselj.metamethods.__typename(self)
                return ("BesselJ(%s)"):format(tostring(T))
            end
            base.AbstractBase(besselj)

            besselj.traits.eltype = T
            besselj.traits.ninit = 1
            besselj.traits.depth = 3

            local Integer = concepts.Integer
            local Stack = concepts.Stack(T)
            terraform besselj:getcoeff(n: I, y: &S)
                where {I: Integer, S: Stack}
                y:set(0, -1)
                y:set(1, (2 * n) / self.x)
                y:set(2, -1)
                y:set(3, 0)
            end

            terraform besselj:getinit(y0: &S) where {S: Stack}
                y0:set(0, tmath.j0(self.x))
            end

            local RecDiff = recdiff.RecDiff(T)
            assert(RecDiff(besselj))

            local N0 = 15
            local dvec = darray.DynamicVector(T)
            terracode
                var alloc: DefaultAlloc
                var y = dvec.new(&alloc, N0)
                var x = escape
                    local val = 1.3
                    if isdual then
                        emit quote in T {val, 1} end
                    else
                        emit quote in [T](val) end
                    end
                end
                var bj = besselj {x}
                recdiff.olver(&alloc, &bj, &y)
            end

            for k = 0, N0 - 1 do
                test tmath.isapprox(y(k), tmath.jn(k, x), tol)
            end
        end
    end
end
