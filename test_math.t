-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

local tmath = require('mathfuns')
local io = terralib.includec("stdio.h")
local C = terralib.includec("string.h")

local funs_single_var = {
    "sin",
    "cos",
    "tan",
    "asin",
    "acos",
    "atan",
    "sinh",
    "cosh",
    "tanh",
    "asinh",
    "acosh",
    "atanh",
    "exp",
    "exp2",
    "log",
    "log10",
    "sqrt",
    "cbrt",
    "erf",
    "erfc",
    --"gamma",
    --"loggamma",
    "abs"
}

testenv "All single variable math functions" do
    --test correctness of output type
    for k,f in ipairs(funs_single_var) do
        local mathfun = tmath[f]
        testset(f) "fun " do
            terracode
                var xfloat = mathfun([float](0))
                var xdouble = mathfun([double](0))
            end
            test [xfloat.type == float]
            test [xdouble.type == double]
        end        
    end
end

testenv "Correctness of selected math functions" do
    testset "special values" do
        for _, T in ipairs({float, double, int8, int16, int32, int64, uint8, uint16, uint32, uint64}) do
            test [T:zero()] == 0
            test [T:unit()] == 1
        end
        test tmath.isapprox(tmath.pi, [math.pi], 1e-15) --compare with Lua's value
        test [float:eps()] == 0x1p-23
        test [double:eps()] == 0x1p-52
    end

    testset "printing" do
        --some printing tests
        local format = tmath.numtostr.format[double]
        terracode
            format = "%0.2f"
            var s1 = tmath.numtostr(1)
            var s2 = tmath.numtostr(1.999999999999)
            format = "%0.3e"
            var s3 = tmath.numtostr(1.999999999999)
        end
        test C.strcmp(&s1[0], "1") == 0
        test C.strcmp(&s2[0], "2.00") == 0
        test C.strcmp(&s3[0], "2.000e+00") == 0
    end

    testset "sqrt" do
        test tmath.isapprox(tmath.sqrt([float](4)), 2.0f, 1e-7f) 
        test tmath.isapprox(tmath.sqrt([double](4)), 2.0, 1e-15) 
    end

    testset "log" do
        test tmath.isapprox(tmath.log([float](1)), 0, 1e-7f) 
        test tmath.isapprox(tmath.log([double](1)), 0, 1e-15) 
    end

    testset "sin" do
        test tmath.isapprox(tmath.sin([float](tmath.pi)), 0, 1e-7f) 
        test tmath.isapprox(tmath.sin([double](tmath.pi)), 0, 1e-15) 
    end

    testset "cos" do
        test tmath.isapprox(tmath.cos([float](tmath.pi)), -1, 1e-7f) 
        test tmath.isapprox(tmath.cos([double](tmath.pi)), -1, 1e-15) 
    end

    testset "j0" do
        if not tmath.expert.isspecial("j0") then
            test tmath.isapprox(tmath.j0(1.0f), 0.7651976865579666f, 1e-7f)
        end
        test tmath.isapprox(tmath.j0(1.0), 0.7651976865579666, 1e-15)
    end

end
