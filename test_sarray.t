import "terraform"
local io = terralib.includec("stdio.h")
local range = require("range")
local sarray = require("sarray")
local matrix = require("matrix")
local nfloat = require("nfloat")
local complex = require("complex")
local concepts = require("concepts")

local complex = require("complex")
local nfloat = require("nfloat")
local concepts = require("concepts")
local tmath = require("mathfuns")

local cfloat = complex.complex(float)
local cdouble = complex.complex(double)
local cint = complex.complex(int)
local float128 = nfloat.FixedFloat(128)
local cfloat128 = complex.complex(float128)
local float256 = nfloat.FixedFloat(256)

import "terratest/terratest"

local checkall, checkallcartesian
local Range = concepts.Range

local SVector = sarray.StaticVector(float, 3)
local SMatrix = sarray.StaticMatrix(float, {2, 3}, {perm={1,2}} )
local SArray3f = sarray.StaticArray(float, {2, 3, 4}, {perm={1,2,3}} )
local SArray4i = sarray.StaticArray(int, {2, 2, 2, 3}, {perm={1,2,3,4}} )

local SMatrix23ci = sarray.StaticMatrix(cfloat128, {2, 3}, {perm={1,2}} )

local im = cfloat128:unit()

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
    io.printf("re(I) = %0.0f\n", im:real())
    io.printf("im(I) = %0.0f\n", im:imag())
    C:print()

    var D = SMatrix23ci.zeros()
    D(0, 1) = 2.0*im + 1.0
    var E = D:transpose()
    D:print()
    E:print()
end
main()

terraform checkall(A : &V, v : T) where {V : Range, T : concepts.Number}
    for a in A do
        if a ~= v then
            return false
        end
    end
    return true
end

terraform checkall(A : &V, rn : &R) where {V : Range, R : Range}
    for t in range.zip(A, rn) do
        var a, v = t
        if a ~= v then
            return false
        end
    end
    return true
end

terraform checkall(A : &V, rn : R) where {V : Range, R : Range}
    return checkall(A, &rn)
end

terraform checkallcartesian(A : &V, v : T) where {V : Range, T : concepts.Number}
    for indices in A:cartesian_indices() do
        if A(unpacktuple(indices)) ~= v then
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

--testing 3D array of one fixed size {2,3,4} and different permutations
for _,Perm in ipairs{ {3,2,1}, {1,2,3} } do
    for _,T in ipairs{int, double} do

        testenv(skip,T, Perm) "Arbitrary dimension arrays" do

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

--testing static vectors of different length and type
for _,T in ipairs{int32,float,double,float256} do
    for N=2,4 do
        testenv(skip, N, T) "Static Vector" do
            
            local SVector = sarray.StaticVector(T, N)

            testset "new, size, get, set" do
                terracode
                    var v = SVector.new()
                    for i=0,N do              
                        v:set(i, i+1)
                    end                     
                end
                test v:length()==N
                for i=0,N-1 do              
                    test v:get(i) == T(i+1)
                end 
            end
            
            testset "zeros" do                       
                terracode                                  
                    var v = SVector.zeros()
                end
                test v:length()==N
                for i=0,N-1 do              
                    test v:get(i) == 0
                end 
            end 
        
            testset "ones" do                       
                terracode                                  
                    var v = SVector.ones()
                end 
                test v:length()==N
                for i=0,N-1 do              
                    test v:get(i) == T(1)
                end 
            end 

            testset "all" do                       
                terracode                                  
                    var v = SVector.all(T(3))
                end 
                test v:length()==N
                for i=0,N-1 do              
                    test v:get(i) == T(3)
                end 
            end 
            
        end
    end --N

    testenv(skip) "Static Vector - Fixed N" do

        testset "from (N=2)" do
            local SVector = sarray.StaticVector(T, 2)
            terracode
                var v = SVector.from{1, 2}
            end
            test v:length() == 2
            test v:get(0) == 1
            test v:get(1) == 2
        end

        testset "from (N=3)" do
            local SVector = sarray.StaticVector(T, 3)
            terracode
                var v = SVector.from{1, 2, 3}
            end
            test v:length() == 3
            test v:get(0) == 1
            test v:get(1) == 2
            test v:get(2) == 3
        end

        testset "copy (N=4)" do
            local SVector = sarray.StaticVector(T, 4)
            terracode
                var v = SVector.from{1, 2, 3, 4}
                var w = SVector.new()
                w:copy(&v)
            end
            test w:length() == 4
            for i = 0, 3 do
                test w:get(i) == i + 1
            end
        end

        testset "axpy (N=5)" do
            local SVector = sarray.StaticVector(T, 5)
            terracode
                var v = SVector.from{1, 2, 3, 4, 5}
                var w = SVector.from{5, 4, 3, 2, 1}
                w:axpy(T(1), &v)
            end
            test w:length() == 5
            for i = 0, 4 do
                test w:get(i) == 6
            end
        end

        testset "dot (N=6)" do
            local SVector = sarray.StaticVector(T, 6)
            terracode
                var v = SVector.from{1, 2, 3, 4, 5, 6}
                var w = SVector.from{5, 4, 3, 2, 1, 0}
                var res = w:dot(&v)
            end
            test res == 35
        end
    end

end --T

--testing static vectors of different length and type
for _,T in ipairs{float, double, float128, int, cint, cfloat, cdouble, cfloat128} do
    for N=2,4 do
        
        testenv(skip, N, T) "Static Matrix" do

            local SMatrix = sarray.StaticMatrix(T, {N, N})

            testset "new, size, get, set" do
                terracode
                    var A = SMatrix.new()
                    A:fill(2)                
                end
                test A:size(0) == N and A:size(1) == N and A:length() == N * N
                test checkall(&A, T(2))
            end
            
            testset "zeros" do                       
                terracode                                  
                    var A = SMatrix.zeros()
                end
                test A:size(0) == N and A:size(1) == N and A:length() == N * N
                test checkall(&A, T(0))
            end 
        
            testset "ones" do                       
                terracode                                  
                    var A = SMatrix.ones()
                end
                test A:size(0) == N and A:size(1) == N and A:length() == N * N
                test checkall(&A, T(1))
            end 

        end

    end --N

    testenv(T) "Static Matrix - fixed N" do

        local SMatrix = sarray.StaticMatrix(T, {3, 2})
        local SVec2 = sarray.StaticVector(T, 2)
        local SVec3 = sarray.StaticVector(T, 3)

        local Concept = {
            Stack = concepts.Stack(T),
            Vector = concepts.Vector(T),
            Matrix = concepts.Matrix(T),
            Range = concepts.Range
        }

        --test basic concepts
        test [ Concept.Vector(SMatrix)]
        test [ Concept.Range(SMatrix) ]
        test [Concept.Stack(SVec2) and Concept.Stack(SVec3)]
        test [Concept.Matrix(SMatrix)]

        testset "Apply" do
            terracode
                var A = SMatrix.from{{1, 2}, {3, 4}, {5, 6}}
                var x = SVec2.from{1, -1}
                var y = SVec3.zeros()
                var yref = SVec3.from{-1, -1, -1}
                matrix.gemv(T(1), &A, &x, T(0), &y)
            end
            test checkall(&y, &yref)
        end
    end


    testenv(T) "Transposed Static matrix - fixed N" do

        local SMatrix = sarray.StaticMatrix(T, {2, 3})
        local CVector = concepts.Vector(T)

        --test basic concepts
        test [ CVector(SMatrix)]
        test [ Range(SMatrix) ]

        terracode
            var A = SMatrix.from({
                {1, 2, 3},
                {4, 5, 6}
            })
            var B = A:transpose()
        end

        --check of transpose type isa Range
        test [ CVector(B.type.type)]
        test [ Range(B.type.type) ]

        testset "transpose" do
            terracode
                B(0,0) = -1 --By mutating B we can check that B is a transposed view of A, not a copy
            end
            test B:size(1) == A:size(0) and B:size(0) == A:size(1)
            for i = 0, 1 do
                for j = 0, 2 do
                    test B(j, i) == A(i, j)
                end
            end
        end

        testset "transpose of transpose" do
            terracode
                var C = B:transpose()
            end
            test C:size(0) == A:size(0) and C:size(1) == A:size(1)
            test checkall(&A, C)
        end

        local SVec2 = sarray.StaticVector(T, 2)
        local SVec3 = sarray.StaticVector(T, 3)

        testset "Apply" do
            terracode
                var x = SVec2.from{1, -1}
                var y = SVec3.zeros()
                var yref = SVec3.from{-3, -3, -3}
                matrix.gemv(T(1), B, &x, T(0), &y)
            end
            test checkall(&y, &yref)
        end

    end

end --T

