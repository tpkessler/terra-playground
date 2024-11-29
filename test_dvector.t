-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

local Alloc = require('alloc')
local Complex = require('complex')
local Nfloat = require("nfloat")
local DVector = require('dvector')
local stack = require("stack")

local Allocator = Alloc.Allocator
local DefaultAllocator =  Alloc.DefaultAllocator()
local float128 = Nfloat.FixedFloat(128)
local float1024 = Nfloat.FixedFloat(1024)


for _, is_complex in pairs({false, true}) do
for _, S in pairs({int, uint, int64, uint64, float, double, float128, float1024}) do
    local T
    if is_complex then
        T = Complex.complex(S)
    else
        T = S
    end
    testenv(T) "DynamicVector" do
        local dvector = DVector.DynamicVector(T)

        terracode
            var alloc: DefaultAllocator
        end

        testset "new" do
            terracode
                var v = dvector.new(&alloc, 3)
            end
            test v:size() == 3
        end

        testset "all" do
            terracode
                var v = dvector.all(&alloc, 2, 4)
            end
            test v:size() == 2
            test v:get(0) == 4
            test v:get(1) == 4
        end

        testset "zeros" do
            terracode
                var v = dvector.zeros(&alloc, 2)
            end
            test v:size() == 2
            test v:get(0) == 0
            test v:get(1) == 0
        end

        testset "zeros_like" do
            terracode
                var w = dvector.new(&alloc, 3)
                var v = dvector.zeros_like(&alloc, &w)
            end
            test w:size() == 3
            test v:size() == 3
            for i = 0, 2 do
                test v:get(i) == 0
            end
        end

        testset "ones" do
            terracode
                var v = dvector.ones(&alloc, 2)
            end
            test v:size() == 2
            test v:get(0) == 1
            test v:get(1) == 1
        end

        testset "ones_like" do
            terracode
                var w = dvector.new(&alloc, 2)
                var v = dvector.ones_like(&alloc, &w)
            end
            test w:size() == 2
            test v:size() == 2
            test v:get(0) == 1
            test v:get(1) == 1
        end

        testset "from" do
            terracode
                var v = dvector.from(&alloc, 3, 2, 1)
            end
            test v:size() == 3
            test v:get(0) == 3
            test v:get(1) == 2
            test v:get(2) == 1
        end

        testset "copy" do
            terracode
                var w = dvector.from(&alloc, 3, 2, 1)
                var v = dvector.like(&alloc, &w)
                v:copy(&w)
            end
            test v:size() == 3
            test v:get(0) == 3
            test v:get(1) == 2
            test v:get(2) == 1
        end

        local dstack = stack.DynamicStack(T)

        testset "__move from a dstack" do
            terracode
                var s = dstack.new(&alloc, 3)
                s:push(1.0)
                s:push(2.0)
                var v : dvector = s:__move()
            end
            test s.data:isempty()
            test v.data:owns_resource()
            test v:size() == 2
            test v(0) == 1.0 and v(1) == 2.0
        end

        testset "iterator" do
            terracode
                var x = dvector.from(&alloc, 3, 2, 1)
                var y = dvector.from(&alloc, 1, 2, 3, 4)
                y.inc = 2
                y.size = 4 / y.inc
                var sumx: T = 0
                for xx in x do
                    sumx = sumx + xx
                end

                var prody: T = 1
                for yy in y do
                    prody = prody * yy
                end
            end

            test sumx == 6
            test prody == 3
        end
    end
end
end
