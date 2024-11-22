-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

local nfloat = require("nfloat")
local mathfun = require("mathfuns")

local suffix = {64, 128, 192, 256, 384, 512, 1024, 2048, 4096}
for _, N in pairs(suffix) do
    testenv(N) "Float" do
        local T = nfloat.FixedFloat(N)
        testset "from" do
            terracode
                var asdouble = T.from(3.5)
                var asstr = T.from("3.5")
            end
            test asdouble == asstr
        end
        testset "cast" do
            terracode
                var asstr = T.from("-3.5")
                var ascast: T = -3.5
                var one = T.from(1)
                var onecast: T = 1
                var exp = T.from(2.5e3)
                var expcast: T = 2.5e3
            end
            test asstr == ascast
            test one == onecast
            test exp == expcast
        end

        testset "add" do
            terracode
                var one: T = 1
                var two: T = 2
                var three:T = 3
            end
            test one + two == three
        end

        testset "sub" do
            terracode
                var one: T = 1
                var two: T = 2
                var three:T = 3
            end
            test three - two == one
        end

        testset "mul" do
            terracode
                var a: T = 4.5
                var b: T = 10.0
                var c: T = 45.0
            end
            test a * b == c
        end

        testset "div" do
            terracode
                var a: T = 4.5
                var b: T = 4.0
                var c: T = 1.125
            end
            test a / b == c
        end
    end
end
