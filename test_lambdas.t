-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"
local lambda = require("lambdas")

testenv "lambda's" do

    local lambda_t = lambda.generate{signature={double,double} -> {double}}

    testset "no captures" do
        terracode
<<<<<<< HEAD
            var p = lambda_t{[terra(a : double, b : double) return a*b end]}
=======
            var p = lambda.new([terra(i : int) return i * i end]) 
>>>>>>> range-terraform
        end
        test p(1.0, 2.0)==2.0
        test p(2.0, 2.0)==4.0
	end

    lambda_t = lambda.generate{signature={double,double} -> {double}, captures={double}}

    testset "with captures" do
        terracode
<<<<<<< HEAD
            var p = lambda_t{[terra(a : double, b : double) return a*b end], {2.0}}
=======
            var x, y = 2, 3
            var p = lambda.new([terra(i : int, x : int, y : int) return i * i * x * y end], x, y) 
>>>>>>> range-terraform
        end
        test p(1.0)==2.0
        test p(2.0)==4.0
	end

    lambda_t.metamethods.__entrymissing = macro(function(entryname, self)
        if entryname=="b" then
            return `self.captures._0
        end
    end)

    testset "access to captures" do
        terracode
            var p = lambda_t{[terra(a : double, b : double) return a*b end], {1.0}}
            p.b = 2.0
        end
        test p(1.0)==2.0
        test p(2.0)==4.0
	end

end