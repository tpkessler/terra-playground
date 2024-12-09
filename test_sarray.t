import "terraform"
local io = terralib.includec("stdio.h")
local range = require("range")
local sarray = require("sarray")
local nfloat = require("nfloat")
local concept = require("concept")

local float1024 = nfloat.FixedFloat(1024)

import "terratest/terratest"

local checkall, checkallcartesian

local Range = concept.Concept:new("Range", function(self, T) return T.isrange==true end)

local SVector = sarray.StaticVector(float, 3)
local SMatrix = sarray.StaticMatrix(float, {2, 3}, {perm={1,2}} )
local SArray3f = sarray.StaticArray(float, {2, 3, 4}, {perm={1,2,3}} )
local SArray4i = sarray.StaticArray(int, {2, 2, 2, 3}, {perm={1,2,3,4}} )

terra main()
    var v = SVector.from({1, 2, 3})
    v:print()

    var A = SMatrix.from({
        {1, 2, 3},
        {4, 5, 6}
    })
    A:print()

    var B = SArray3f.from({{
        {1, 2, 3, 4},
        {5, 6, 7, 8},
        {9, 10, 11, 12},
    },{
        {1, 2, 3, 4},
        {5, 6, 7, 8},
        {9, 10, 11, 12},
    }})
    B:print()

    var C = SArray4i.from({{{
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
        {1, 2, 3},
        {4, 5, 6},
    }}})

    C:print()
end
main()

terraform checkall(A : &V, v : T) where {V : Range, T : concept.Number}
    for a in A do
        if a ~= v then
            return false
        end
    end
    return true
end

terraform checkallcartesian(A : &V, v : T) where {V : Range, T : concept.Number}
    for indices in A:cartesian_indices() do
        if A(unpacktuple(indices)) ~= v then
            return false
        end
    end
    return true
end

terraform checkall(A : &V, rn : R) where {V, R : Range}
    for t in range.zip(@A, rn) do
        var a, v = t
        if a ~= v then
            return false
        end
    end
    return true
end

terraform checkallcartesian(A : &V, rn : R) where {V : Range, R : Range}
    for t in range.zip(A:cartesian_indices(), rn) do
        var indices, v = t
        if A(unpacktuple(indices)) ~= v then
            return false
        end
    end
    return true
end

for _,Perm in ipairs{ {3,2,1}, {1,2,3} } do
    for _,T in ipairs{int, double} do

        testenv(T, Perm) "Arbitrary dimension arrays" do

            local linrange = range.Unitrange(T)
            local SArray = sarray.StaticArray(T, {2, 3, 4}, {perm=Perm} )

            terracode
                var A : SArray
                var B : SArray
                for count, indices in range.enumerate(A:cartesian_indices()) do
                    A:set(unpacktuple(indices), count)
                end
                for count, indices in range.enumerate(B:cartesian_indices()) do
                    B:set(unpacktuple(indices), count)
                end
            end

            testset "size, length, set, get, perm" do
                test A:size(0) == 2 and A:size(1) == 3 and A:size(2) == 4
                test A:perm(0) == [ Perm[1] ] and A:perm(1) == [ Perm[2] ] and A:perm(2) == [ Perm[3] ]
                test A:length() == 24
                test checkall(&A, linrange{0,24})
                test checkallcartesian(&A, linrange{0,24})
            end

            testset "apply" do
                test checkall(&B, linrange{0,24})
                test checkallcartesian(&B, linrange{0,24})
            end

            testset "all, ones, zeros" do
                terracode
                    var C = SArray.all(2)
                end
                test checkall(&C, 2)
            end

            testset "copy" do
                terracode
                    var Y = SArray.all(2)
                    var X : SArray
                    X:copy(&Y)
                end
                test checkall(&X, 2)
            end

            testset "fill" do
                terracode
                    var X : SArray
                    X:fill(2)
                end
                test checkall(&X, 2)
            end

            testset "scal" do
                terracode
                    var X = SArray.all(2)
                    X:scal(2)
                end
                test checkall(&X, 4)
            end

            testset "axpy" do
                terracode
                    var X = SArray.all(2)
                    var Y = SArray.all(3)
                    Y:axpy(4, &X)
                end
                test checkall(&Y, 11)
            end

            testset "dot" do
                terracode
                    var X = SArray.all(2)
                    var Y = SArray.all(3)
                    var s = Y:dot(&X)
                end
                test s == 24 * 6
            end

            testset "norm" do
                terracode
                    var X = SArray.all(2)
                    var s1 = X:norm2()
                end
                test s1 == 24 * 4
            end

            testset "ranges" do
                terracode
                    var s = 0
                    for a in A do
                        s = s + a
                    end
                end
                test s == 12 * 23
            end

        end -- testenv(T,Perm)

    end
end


for _,T in ipairs{int, double} do

    testenv(T) "Matrix views" do

        local SMatrix = sarray.StaticMatrix(T, {2, 3}, {perm={1,2}} )

        terracode
            var A = SMatrix.from({
                {1, 2, 3},
                {4, 5, 6}
            })
        end

        testset "transpose" do
            terracode
                var B = A:transpose()
                B(0,0) = -1 --By checking that A and B are eachothers transpose
                --we can see that B is a trnasposed view of A, not a copy
            end
            test B:size(1) == A:size(0) and B:size(0) == A:size(1)
            for i = 0, 1 do
                for j = 0, 2 do
                    test B(j, i) == A(i, j)
                end
            end
        end

    end

end

