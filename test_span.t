-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local span = require("span")
local stack = require("stack")

import "terratest/terratest"

local N = 3
local DefaultAllocator = alloc.DefaultAllocator()

for _, T in pairs{float, double, int32, int64} do
    local stackT = stack.DynamicStack(T)
    local spanDynamic = span.Span(T)
    local spanFixed = span.Span(T, N)
    for _, spanT in pairs{spanDynamic, spanFixed} do
        testenv(spanT) "Basic operations" do
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
                    var sp = spanT {&a[0], N}
                end
                for i = 1, N do
                    test a[i - 1] == sp(i - 1)
                end
            end

            testset "Iterator" do
                terracode
                    var A: DefaultAllocator
                    var a = arrayof(T, 1, -2, 3)
                    var sp = spanT {&a[0], 3}
                    var st = stackT.new(&A, 5)
                    sp:pushall(&st)
                end
                for i = 1, 3 do
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

            testset "Cast from pointer" do
                terracode
                    var a = arrayof(T, -4, -5, 11)
                    var sa: spanT = &a[0]
                end

                test sa(0) == a[0]
                if spanT.traits.length == N then
                    test sa(1) == a[1]
                    test sa(2) == a[2]
                end
            end
        end
    end
end
