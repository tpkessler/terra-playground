-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

local math = require('mathfuns')

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
    "gamma",
    "loggamma",
    "abs"
}

testenv "All single variable math functions" do
    --test correctness of output type
    for k,f in ipairs(funs_single_var) do
        local mathfun = math[f]
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
    --test if result is correct
    testset "sqrt" do
        test math.isapprox(math.sqrt([float](4)), 2.0, 1e-15) 
        test math.isapprox(math.sqrt([double](4)), 2.0, 1e-15) 
    end

    testset "log" do
        test math.isapprox(math.log([float](1)), 0, 1e-15) 
        test math.isapprox(math.log([double](1)), 0, 1e-15) 
    end

    testset "sin" do
        test math.isapprox(math.sin([float](math.pi)), 0, 1e-15) 
        test math.isapprox(math.sin([double](math.pi)), 0, 1e-15) 
    end

    testset "cos" do
        test math.isapprox(math.cos([float](math.pi)), 1, 1e-15) 
        test math.isapprox(math.cos([double](math.pi)), 1, 1e-15) 
    end

end