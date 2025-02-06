-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local span = require("span")
local stack = require("stack")

import "terratest/terratest"

local T = double
local N = 6

local DefaultAllocator = alloc.DefaultAllocator()
local spanT = span.Span(T)
local stackT = stack.DynamicStack(T)

testenv "Basic operations" do
    testset "Type" do
        terracode
            var a: T[N]
            var sp = spanT {&a[0], N}
        end
        test [sp.type == spanT]
    end

    testset "Element access" do
        terracode
            var a = arrayof(T, -1, 2, 4)
            var sp = spanT {&a[0], 3}
        end
        for i = 1, 3 do
            test a[i - 1] == sp(i - 1)
        end
    end

    testset "Iterator" do
        terracode
            var A: DefaultAllocator
            var a = arrayof(T, 1, -2, 3, -4, 5, -6)
            var sp = spanT {&a[0], 6}
            var st = stackT.new(&A, 10)
            var it = sp:getiterator()
            sp:pushall(&st)
        end
        for i = 1, 6 do
            test a[i - 1] == st(i - 1)
        end
    end

    testset "Cast from tuple" do
        local terra modify(x: spanT)
            for i = 0, x:size() do
                x(i) = x(i) + 1
            end
        end
        terracode
            var a = arrayof(T, -1, -2, -3)
            modify({&a[0], 3})
        end

        test a[0] == 0
        test a[1] == -1
        test a[2] == -2
    end

    testset "Cast from array" do
        terracode
            var a = arrayof(T, 0, -1, -2)
            var sa: spanT = a
        end

        test sa(0) == 0
        test sa(1) == -1
        test sa(2) == -2
    end

    testset "Cast from list" do
        terracode
            var sa: spanT = {0, -1, -2}
        end

        test sa(0) == 0
        test sa(1) == -1
        test sa(2) == -2
    end
end
