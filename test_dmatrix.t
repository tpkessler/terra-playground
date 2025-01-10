-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

local matrix = require("matrix")
local dmatrix = require("dmatrix")
local dvector = require("dvector")
local alloc = require("alloc")
local complex = require("complex")
local nfloat = require("nfloat")
local concepts = require("concepts")

local cfloat = complex.complex(float)
local cdouble = complex.complex(double)
local cint = complex.complex(int64)
local float128 = nfloat.FixedFloat(128)
local cfloat128 = complex.complex(float128)

local DefaultAlloc = alloc.DefaultAllocator()

for _, T in pairs({double, float, int64, cdouble, cfloat, cint, float128, cfloat128}) do

    local Vec = dvector.DynamicVector(T)
    local Mat = dmatrix.DynamicMatrix(T)
    testenv(T) "Basic operations" do
        testset "Init" do
            terracode
                var alloc: DefaultAlloc
                var rows = 3
                var cols = 2
                var m = Mat.new(&alloc, rows, cols)
            end
            test m:rows() == rows
            test m:cols() == cols
        end

        testset "Zeros" do
            terracode
                var alloc: DefaultAlloc
                var rows = 3
                var cols = 2
                var m = Mat.zeros(&alloc, rows, cols)
            end
            test m:rows() == rows
            test m:cols() == cols
            for i = 0, 2 do
                for j = 0, 1 do
                    test m:get(i, j) == 0
                end
            end
        end

        testset "From" do
            terracode
                var alloc: DefaultAlloc
                var m = Mat.from(&alloc, {{1, 2, 3}, {4, 5, 6}})
            end
            test m:rows() == 2
            test m:cols() == 3
            for i = 0, 1 do
                for j = 0, 2 do
                    test m:get(i, j) == j + 3 * i + 1
                end
            end
        end

        testset "Like" do
            terracode
                var alloc: DefaultAlloc
                var rows = 7
                var cols = 4
                var a = Mat.new(&alloc, rows, cols)
                var b = Mat.like(&alloc, &a)
            end
            test a:rows() == b:rows()
            test a:cols() == b:cols()
        end

        testset "Zeros like" do
            terracode
                var alloc: DefaultAlloc
                var rows = 7
                var cols = 4
                var a = Mat.new(&alloc, rows, cols)
                var b = Mat.zeros_like(&alloc, &a)
            end
            test a:rows() == b:rows()
            test a:cols() == b:cols()
            for i = 0, 6 do
                for j = 0, 3 do
                    test b:get(i, j) == 0
                end
            end
        end
    end

    testenv(T) "Matrix base" do
        testset "Fill" do
            terracode
                var alloc: DefaultAlloc
                var a = Mat.new(&alloc, 2, 2)
                a:fill(3)
            end
            for i = 0, 1 do
                for j = 0, 1 do
                    test a:get(i, j) == 3
                end
            end
        end

        testset "Clear" do
            terracode
                var alloc: DefaultAlloc
                var a = Mat.new(&alloc, 2, 2)
                a:clear()
            end
            for i = 0, 1 do
                for j = 0, 1 do
                    test a:get(i, j) == 0
                end
            end
        end

        testset "Copy" do
            terracode
                var alloc: DefaultAlloc
                var a = Mat.from(&alloc, {{1, 2}, {3, 4}, {5, 6}})
                var b = Mat.like(&alloc, &a)
                var c = Mat.new(&alloc, 2, 3)
                b:copy(false, &a)
                c:copy(true, &a)
            end
            for i = 0, 2 do
                for j = 0, 1 do
                    test b:get(i, j) == a:get(i, j)
                    test c:get(j, i) == a:get(i, j)
                end
            end
        end

        testset "Swap" do
            terracode
                var alloc: DefaultAlloc
                var a = Mat.from(&alloc, {{1, 2}, {3, 4}, {5, 6}})
                var b = Mat.from(&alloc, {{5, 6}, {1, 2}, {3, 4}})
                var c = Mat.like(&alloc, &a)
                var d = Mat.like(&alloc, &b)
                c:copy(false, &a)
                d:copy(false, &b)
                a:swap(false, &b)
            end
            for i = 0, 2 do
                for j = 0, 1 do
                    test a:get(i, j) == d:get(i, j)
                    test b:get(i, j) == c:get(i, j)
                end
            end
        end

        testset "Apply" do
            terracode
                var alloc: DefaultAlloc
                var a = Mat.from(&alloc, {{1, 2}, {3, 4}, {5, 6}})
                var x = Vec.from(&alloc, 1, -1)
                var y = Vec.zeros(&alloc, 3)
                var yref = Vec.from(&alloc, -1, -1, -1)
                a:apply(false, [T](1), &x, [T](0), &y)
            end
            for i = 0, 2 do
                test y:get(i) == yref:get(i)
            end
        end

        testset "Mul" do
            terracode
                var alloc: DefaultAlloc
                var a = Mat.from(&alloc, {{1, 2}, {3, 4}})
                var b = Mat.from(&alloc, {{2, -1}, {-1, 2}})
                var c = Mat.zeros_like(&alloc, &a)
                matrix.scaledaddmul([T](1), false, &a, false, &b, [T](0), &c)
                var cref = Mat.from(&alloc, {{0, 3}, {2, 5}})
                var ct = Mat.zeros_like(&alloc, &a)
                var ctref = Mat.from(&alloc, {{-1, 5}, {0, 6}})
                matrix.scaledaddmul([T](1), true, &a, false, &b, [T](0), &ct)
            end
            test c:rows() == 2
            test c:cols() == 2
            for i = 0, 1 do
                for j = 0, 1 do
                    test c:get(i, j) == cref:get(i, j)
                end
            end

            test ct:rows() == 2
            test ct:cols() == 2
            for i = 0, 1 do
                for j = 0, 1 do
                    test ct:get(i, j) == ctref:get(i, j)
                end
            end
        end

        if concepts.Complex(T) then
            testset "Mul complex" do
                terracode
                    var alloc: DefaultAlloc
                    var I = [T:unit()]
                    var a = Mat.from(&alloc, {{1 + 4 * I, 2 + 3 * I}, {3 + 2 * I, 4 + I}})
                    var b = Mat.from(&alloc, {{2, -1 - I}, {-1 + I, 2}})
                    var c = Mat.zeros_like(&alloc, &a)
                    var cref = Mat.from(&alloc, {{-3 + 7 * I, 7 + I}, {1 + 7 * I, 7 - 3 * I}})
                    matrix.scaledaddmul([T](1), false, &a, true, &b, [T](0), &c)
                end
                test c:rows() == 2
                test c:cols() == 2
                for i = 0, 1 do
                    for j = 0, 1 do
                        test c:get(i, j) == cref:get(i, j)
                    end
                end
            end
        end
    end
end
