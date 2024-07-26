<<<<<<< HEAD
-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

local Alloc = require('alloc')
local Complex = require('complex')
local Nfloat = require("nfloat")
local DVector = require('dvector')

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
    end
end
end
=======
import "terratest/terratest"

local Alloc = require('alloc')
local DVector = require('dvector')

local Allocator = Alloc.Allocator

local DefaultAllocator =  Alloc.DefaultAllocator()
local dvector = DVector.DynamicVector(double)


testenv "DynamicVector" do

    terracode
        var alloc : DefaultAllocator
    end

    testset "new" do
        terracode
            var v = dvector.new(&alloc, 3)
        end
        test v:size() == 3
    end

    testset "fill" do
        terracode
            var v = dvector.fill(&alloc, 2, 4.5)
        end
        test v:size() == 2
        test v:get(0) == 4.5
        test v:get(1) == 4.5
    end

    testset "zeros" do
        terracode
            var v = dvector.zeros(&alloc, 2)
        end
        test v:size() == 2
        test v:get(0) == 0.0
        test v:get(1) == 0.0
    end

    testset "ones" do
        terracode
            var v = dvector.ones(&alloc, 2)
        end
        test v:size() == 2
        test v:get(0) == 1.0
        test v:get(1) == 1.0
    end

    testset "from" do
        terracode
            var v = dvector.from(&alloc, 0.0, 0.5, 1.1)
        end
        test v:size() == 3
        test v:get(0) == 0.0
        test v:get(1) == 0.5
        test v:get(2) == 1.1
    end

end
>>>>>>> 4e595ec (Gaussian quadrature rules (#10))
