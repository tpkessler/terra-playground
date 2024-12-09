-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local sparse = require("sparse")
local nfloat = require("nfloat")
local complex = require("complex")

local complexDouble = complex.complex(double)
local float256 = nfloat.FixedFloat(256)

import "terratest/terratest"

local Alloc = alloc.DefaultAllocator()
for _, T in pairs({float, double, float256, complexDouble}) do
    local CSR = sparse.CSRMatrix(T)
    testenv(T) "Sparse CSR Matrix" do
        terracode
            var alloc: Alloc
            var n = 3
            var m = 4
            var a = CSR.new(&alloc, n, m)
        end

        testset "Dimensions" do
            test a:rows() == n
            test a:cols() == m
        end

        local io = terralib.includec("stdio.h")
        testset "Set and Get" do
            terracode
                var i = 1
                var j = 2
                var x: T = -2
                a:set(i, j, x)
                var y = a:get(i, j)
                a:set(i, j, -x)
                var z = a:get(i, j)
                a:set(j, i, 2 * x)
                var w = a:get(j, i)
            end
            test y == x
            test z == -x
            test w == 2 * x
        end
    end
end
