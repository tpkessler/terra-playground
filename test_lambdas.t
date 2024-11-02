-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"
local lambda = require("lambdas")

testenv "lambda's" do

    testset "no captures" do
        terracode
            var p = lambda.new([terra(i : int) return i * i end]) 
        end
        test p(1) == 1
        test p(2) == 4
	end

    testset "with captured vars" do
        terracode
            var x, y = 2, 3
            var p = lambda.new([terra(i : int, x : int, y : int) return i * i * x * y end], {z = x, y = y}) 
        end
        test p(1) == 6
        test p(2) == 24
	end

end