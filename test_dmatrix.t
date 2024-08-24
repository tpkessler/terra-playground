import "terratest/terratest"

local dmatrix = require("dmatrix")
local dvector = require("dvector")
local alloc = require("alloc")
local complex = require("complex")

local cfloat = complex.complex(float)
local cdouble = complex.complex(double)
local cint = complex.complex(int64)

local DefaultAlloc = alloc.DefaultAllocator()

for _, T in pairs({double, float, int32, int64, cdouble, cfloat, cint}) do
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
    end
end
