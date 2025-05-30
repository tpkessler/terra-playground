-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local parametrized = require("parametrized")
local concepts = require("concepts")

import "terratest"
import "terraform"

testenv "Parametrized types" do
    local Point = parametrized.type(function(T)
        local struct point {
            x: T
            y: T
        }
        return point
    end)

    local Complex = parametrized.type(function(T)
        local struct complex {
            re: T
            im: T
        }
        return complex
    end)

    testset "Caching" do
        local p1 = Point(int32)
        local p2 = Point(int32)

        test [p1 == p2]
    end

    testset "Concept" do
        local C = Point(concepts.Integer)
        local D = Complex(concepts.Integer)
        local T = Point(int32)
        local S = Point(double)

        test [concepts.isconcept(C)]
        test [concepts.isconcept(D)]
        test [C(T)]
        test [C(S) == false]
        test [D(T) == false]
    end

    testset "Overloaded functions" do
        local terraform process(x: T) where {T: Point(concepts.Integer)}
            return x.x + x.y
        end
        terraform process(x: T) where {T: Point(concepts.Float)}
            return x.x - x.y
        end

        terracode
            var x = [Point(int)]({2, 3})
            var y = [Point(double)]({2.0, 3.0})
        end

        test process(x) == 5
        test process(y) == -1.0
    end
end
