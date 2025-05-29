-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

local C = terralib.includec("string.h")
local nfloat = require("nfloat")
local tmath = require("tmath")


local suffix = {64, 128, 192, 256, 384, 512, 1024, 2048, 4096}
for _, N in pairs(suffix) do
    testenv(N) "Float" do
        local T = nfloat.FixedFloat(N)
        testset "constants: zero, one" do
            local zero = T:zero()
            local unit = T:unit()
            local eps = T:eps()
            test zero == 0
            test unit == 1
            test [T:eps()] == 0.5 * tmath.pow(T(2), -N)
        end
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
        
        testset "truncate to double" do
            terracode 
                var u = T(0)
                var v = T(1)
                var w = T(2.934592)
                var x = T(-1)
            end
            test u:truncatetodouble() == 0.0
            test v:truncatetodouble() == 1.0
            test w:truncatetodouble() == 2.934592
            test x:truncatetodouble() == -1.0
        end

        testset "printing" do
            --some printing tests
            local format = tmath.numtostr.format[T]
            terracode
                var s1 = tmath.numtostr(T(1))
                var s2 = tmath.numtostr(T(1.999999999999))
                format = "%0.3f"
                var s3 = tmath.numtostr(T(1))
                var s4 = tmath.numtostr(T(1.999999999999))
            end
            test C.strcmp(&s1[0], "1.00") == 0
            test C.strcmp(&s2[0], "2.00") == 0
            test C.strcmp(&s3[0], "1.000") == 0
            test C.strcmp(&s4[0], "2.000") == 0
        end
    end
end
