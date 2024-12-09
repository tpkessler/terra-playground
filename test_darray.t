-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local darray = require("darray")
local complex = require('complex')
local nfloat = require("nfloat")

local DefaultAllocator = alloc.DefaultAllocator()

local DVector = darray.DynamicArray(float, 1)
local DMatrix = darray.DynamicArray(int, 2, {perm={2,1}} )
local DArray3f = darray.DynamicArray(float, 3, {perm={3,2,1}} )
local DArray4i = darray.DynamicArray(int, 4, {perm={4,3,2,1}} )

--test printing of dynamic arrays
terra main()
    var alloc : DefaultAllocator

    --vector
    var v = DVector.from(&alloc, {1, 2, 3, -1})
    v:print()

    --matrix
    var A = DMatrix.from(&alloc, {
        {1, 2, 3},
        {-1, -2, -3}
    })
    A:print()

    --3D array
    var B = DArray3f.from(&alloc, {{
        {1, 2, 3, 4},
        {5, 6, 7, 8},
        {9, 10, 11, 12},
    },{
        {-1, -2, -3, -4},
        {-5, -6, -7, -8},
        {-9, -10, -11, -12},
    }})
    B:print()

    --4D array
    var C = DArray4i.from(&alloc, {{{
        {1, 2, 3},
        {4, 5, 6},
    },
    {
        {1, 2, 3},
        {4, 5, 6},
    }},
    {{
        {1, 2, 3},
        {4, 5, 6},
    },
    {
        {-1, -2, -3},
        {-4, -5, -6},
    }}})
    C:print()

end
main()


import "terratest/terratest"

local float256 = nfloat.FixedFloat(256)

--for _, is_complex in pairs({false, true}) do
--for _, S in pairs({int, uint, int64, uint64, float, double, float256}) do

for _, is_complex in pairs({false}) do
for _, S in pairs({int}) do 

    local T = is_complex and complex.complex(S) or S

    testenv(T) "DynamicVector" do
        local dvec = darray.DynamicVector(T)

        terracode
            var alloc : DefaultAllocator
        end

        testset "new, length, get, set" do
            terracode
                var v = dvec.new(&alloc, 3)
                for i=0,3 do              
                    v:set(i, i+1)
                end                     
            end
            test v:length()==3
            for i = 0, 2 do              
                test v:get(i) == T(i+1)
            end 
        end

        testset "all" do
            terracode
                var v = dvec.all(&alloc, 2, 4)
            end
            test v:length() == 2
            test v:get(0) == 4
            test v:get(1) == 4
        end

        testset "zeros" do
            terracode
                var v = dvec.zeros(&alloc, 2)
            end
            test v:length() == 2
            test v:get(0) == 0
            test v:get(1) == 0
        end

        testset "ones" do
            terracode
                var v = dvec.ones(&alloc, 2)
            end
            test v:length() == 2
            test v:get(0) == 1
            test v:get(1) == 1
        end

        testset "from" do
            terracode
                var v = dvec.from(&alloc, {3, 2, 1})
            end
            test v:length() == 3
            test v:get(0) == 3
            test v:get(1) == 2
            test v:get(2) == 1
        end

        testset "copy" do
            terracode
                var v = dvec.from(&alloc, {1, 2, 3, 4})
                var w = dvec.new(&alloc, 4)
                w:copy(&v)
            end
            test w:length() == 4
            for i = 0, 3 do
                test w:get(i) == i + 1
            end
        end

        testset "axpy" do
            terracode
                var v = dvec.from(&alloc, {1, 2, 3, 4, 5})
                var w = dvec.from(&alloc, {5, 4, 3, 2, 1})
                w:axpy(1, &v)
            end
            test w:length() == 5
            for i = 0, 4 do
                test w:get(i) == 6
            end
        end

        testset "dot" do
            terracode
                var v = dvec.from(&alloc, {1, 2, 3, 4, 5, 6})
                var w = dvec.from(&alloc, {5, 4, 3, 2, 1, 0})
                var res = w:dot(&v)
            end
            test res == 35
        end

        testset "range" do
            terracode
                var A = dvec.from(&alloc, {1, 2, 3, 4, 5, 6})
                var res : T = 0
                for a in A do
                    res = res + a
                end
            end
            test res == 21
        end
    end

    testenv(T) "Basic operations" do

        local dvec = darray.DynamicVector(T)
        local dmat = darray.DynamicMatrix(T)

        testset "Init" do
            terracode
                var alloc : DefaultAllocator
                var m = dmat.new(&alloc, {3, 2})
            end
            test m:size(0) == 3 and m:size(1) == 2
        end

        testset "Zeros" do
            terracode
                var alloc : DefaultAllocator
                var m = dmat.zeros(&alloc, {3, 2})
            end
            test m:size(0) == 3 and m:size(1) == 2
            for i = 0, 2 do
                for j = 0, 1 do
                    test m:get(i, j) == 0
                end
            end
        end

        testset "From" do
            terracode
                var alloc : DefaultAllocator
                var m = dmat.from(&alloc, {
                            {1, 2, 3}, 
                            {4, 5, 6}
                })
            end
            test m:size(0) == 2 and m:size(1) == 3
            for i = 0, 1 do
                for j = 0, 2 do
                    test m:get(i, j) == j + 3 * i + 1
                end
            end
        end

    end

    testenv(T) "Matrix base" do

        local dvec = darray.DynamicVector(T)
        local dmat = darray.DynamicMatrix(T)

        testset "Fill" do
            terracode
                var alloc : DefaultAllocator
                var a = dmat.new(&alloc, {2, 2})
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
                var alloc : DefaultAllocator
                var a = dmat.new(&alloc, {2, 2})
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
                var alloc : DefaultAllocator
                var a = dmat.from(&alloc, {{1, 2}, {3, 4}, {5, 6}})
                var b = dmat.new(&alloc, {3,2})
                b:copy(&a)
            end
            for i = 0, 2 do
                for j = 0, 1 do
                    test b:get(i, j) == a:get(i, j)
                end
            end
        end

        testset "Swap" do
            terracode
                var alloc: DefaultAllocator
                var a = dmat.from(&alloc, {{1, 2}, {3, 4}, {5, 6}})
                var b = dmat.from(&alloc, {{5, 6}, {1, 2}, {3, 4}})
                var c = dmat.new(&alloc, {3,2})
                var d = dmat.new(&alloc, {3,2})
                c:copy(&a)
                d:copy(&b)
                a:swap(&b)
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
                var alloc: DefaultAllocator
                var a = dmat.from(&alloc, {{1, 2}, {3, 4}, {5, 6}})
                var x = dvec.from(&alloc, {1, -1})
                var y = dvec.zeros(&alloc, 3)
                var yref = dvec.from(&alloc, {-1, -1, -1})
                a:apply([T](1), &x, [T](0), &y)
            end
            for i = 0, 2 do
                test y:get(i) == yref:get(i)
            end
        end

    end


end
end