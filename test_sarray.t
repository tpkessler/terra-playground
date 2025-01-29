-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local range = require("range")
local sarray = require("sarray")
local matrix = require("matrix")
local nfloat = require("nfloat")
local complex = require("complex")
local concepts = require("concepts")
local tmath = require("tmath")

local float128 = nfloat.FixedFloat(128)
local float256 = nfloat.FixedFloat(256)

local cint = complex.complex(int)
local cfloat = complex.complex(float)
local cdouble = complex.complex(double)
local cfloat128 = complex.complex(float128)

import "terratest/terratest"

if not __silent__ then

    local SVector = sarray.StaticVector(float, 3)
    local SMatrix = sarray.StaticMatrix(float, {2, 3}, {perm={1,2}} )
    local SArray3f = sarray.StaticArray(float, {2, 3, 4}, {perm={1,2,3}} )
    local SArray4i = sarray.StaticArray(int, {2, 2, 2, 3}, {perm={1,2,3,4}} )
    local SMatrix23ci = sarray.StaticMatrix(cfloat128, {3, 2})

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
        C:print()

        var D = SMatrix23ci.zeros()
        D(0, 1) = 2.0*im + 1.0
        var E = D:transpose()
        D:print()
        E:print()
    end
    main()

end --not __silent__

local checkallcartesian
local Range = concepts.Range

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
                test tmath.isapprox(&A, linrange{0,24}, 0)
                test checkallcartesian(&A, linrange{0,24})
            end

            testset "all, ones, zeros" do
                terracode
                    var C = SArray.all(2)
                    var D = SArray.zeros()
                    var E = SArray.ones()
                end
                test tmath.isapprox(&C, 2, 0)
                test tmath.isapprox(&D, 0, 0)
                test tmath.isapprox(&E, 1, 0)
            end

            testset "copy" do
                terracode
                    var Y = SArray.all(2)
                    var X : SArray
                    X:copy(&Y)
                end
                test tmath.isapprox(&X, 2, 0)
            end

            testset "swap" do
                terracode
                    var C = SArray.ones()
                    A:swap(&C)
                end
                test tmath.isapprox(&C, linrange{0,24}, 0)
                test tmath.isapprox(&A, T(1), 0)
            end

            testset "fill" do
                terracode
                    var X : SArray
                    X:fill(2)
                end
                test tmath.isapprox(&X, 2, 0)
            end

            testset "scal" do
                terracode
                    var X = SArray.all(2)
                    X:scal(2)
                end
                test tmath.isapprox(&X, 4, 0)
            end

            testset "axpy" do
                terracode
                    var X = SArray.all(2)
                    var Y = SArray.all(3)
                    Y:axpy(4, &X)
                end
                test tmath.isapprox(&Y, 11, 0)
            end

            testset "dot" do
                terracode
                    var X = SArray.all(2)
                    var Y = SArray.all(3)
                    var s = Y:dot(&X)
                end
                test s == 24 * 6
            end

            testset "norm2" do
                terracode
                    var X = SArray.all(2)
                    var s1 = X:norm2()
                end
                test s1 == 24 * 4
            end

            if concepts.Float(T) then
                testset "norm" do
                    terracode
                        var X = SArray.all(2)
                        var s1 = X:norm()
                    end
                    test tmath.isapprox(s1, tmath.sqrt(24. * 4.), 1e-15)
                end
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
for _,T in ipairs{int,float,double,float256} do
    for N=2,4 do
        testenv(N, T) "Static Vector" do
            
            local SVector = sarray.StaticVector(T, N)

            testset "new, size, get, set" do
                terracode
                    var v = SVector.new()
                    for i=0,N do              
                        v:set(i, i+1)
                    end                     
                end
                test v:length()==N
                --test tmath.isapprox(v, range.Unitrange{1, N+1})
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
            
        end --testenv(T, N) "Static Vector" do
    end --N

    testenv(T) "Static Vector interface - Fixed N" do

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

--testing static matrices of different length and type
for _,T in ipairs{float, double, float128, int, cint, cfloat, cdouble, cfloat128} do
    for N=2,4 do

        local M = N+1
        
        testenv(N, T) "Static Matrix creation" do

            local SMatrix = sarray.StaticMatrix(T, {M, N})

            testset "new, size, get, set" do
                terracode
                    var A = SMatrix.new()
                    A:fill(2)                
                end
                test A:size(0) == M and A:size(1) == N and A:length() == M * N
                test A:rows() == M and A:cols() == N
                test tmath.isapprox(&A, T(2), 0)
            end
            
            testset "zeros" do                       
                terracode                                  
                    var A = SMatrix.zeros()
                end
                test A:size(0) == M and A:size(1) == N and A:length() == M * N
                test tmath.isapprox(&A, T(0), 0)
            end 
        
            testset "ones" do                       
                terracode                                  
                    var A = SMatrix.ones()
                end
                test A:size(0) == M and A:size(1) == N and A:length() == M * N
                test tmath.isapprox(&A, T(1), 0)
            end 

        end --testenv(N, T) "Static Matrix creation" do

    end --N
end --T


for _,T in ipairs{int, float, double, float128} do

    local SMatrix2x2 = sarray.StaticMatrix(T, {2, 2})
    local SMatrix3x2 = sarray.StaticMatrix(T, {3, 2})
    local SMatrix2x3 = sarray.StaticMatrix(T, {2, 3})
    local SVector2 = sarray.StaticVector(T, 2)
    local SVector3 = sarray.StaticVector(T, 3)
    local im = T:unit()

    local Concept = {
        Stack = concepts.Stack(T),
        Vector = concepts.Vector(T),
        Matrix = concepts.Matrix(T),
        Range = concepts.Range
    }

    testenv(T) "Transpose view - Real - fixed N" do
        
        terracode
            var A = SMatrix2x3.from({
                {1, 2, 3},
                {4, 5, 6}
            })
            var B = A:transpose()
        end

        --test basic concepts
        test [ Concept.Vector(SMatrix2x3)]
        test [ Concept.Range(SMatrix2x3) ]
        --check of transpose type isa Matrix, Vector and Range
        test [ Concept.Matrix(B.type.type)]
        test [ Concept.Vector(B.type.type)]
        test [ Concept.Range(B.type.type) ]

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
            test tmath.isapprox(&A, C, 0)
        end

    end

    testenv(T) "GEMV - Real - fixed N" do

        terracode
            var A = SMatrix3x2.from{{1, 2}, {3, 4}, {5, 6}}
        end

        testset "gemv" do
            terracode
                var x = SVector2.from{1, -1}
                var y = SVector3.zeros()
                var yref = SVector3.from{-1, -1, -1}
                matrix.gemv(T(1), &A, &x, T(0), &y)
            end
            test tmath.isapprox(&y, &yref, 0)
        end

        testset "gemv - transpose A" do
            terracode
                var x = SVector3.from{1, -1, 2}
                var y = SVector2.zeros()
                var yref = SVector2.from{8, 10}
                matrix.gemv(T(1), A:transpose(), &x, T(0), &y)
            end
            test tmath.isapprox(&y, &yref, 0)
        end

    end

    testenv(T) "GEMM - Real - fixed N" do
        
        terracode
            var A = SMatrix2x2.from({{1, 2}, {3, 4}})
            var B = SMatrix2x2.from({{2, -1}, {-2, 3}})
            var C = SMatrix2x2.zeros()
        end

        testset "gemm" do
            terracode
                matrix.gemm([T](1), &A, &B, T(0), &C)
                var Cref = SMatrix2x2.from({{-2, 5}, {-2, 9}})
            end
            test tmath.isapprox(&C, &Cref, 0)
        end

        testset "gemm - transpose A" do
            terracode
                matrix.gemm([T](1), A:transpose(), &B, T(0), &C)
                var Cref = SMatrix2x2.from({{-4, 8}, {-4, 10}})
            end
            test tmath.isapprox(&C, &Cref, 0)
        end

        testset "gemm - transpose B" do
            terracode
                matrix.gemm([T](1), &A, B:transpose(), T(0), &C)
                var Cref = SMatrix2x2.from({{0, 4}, {2, 6}})
            end
            test tmath.isapprox(&C, &Cref, 0)
        end

        testset "gemm - transpose A, transpose B" do
            terracode
                matrix.gemm([T](1), A:transpose(), B:transpose(), T(0), &C)
                var Cref = SMatrix2x2.from({{-1, 7}, {0, 8}})
            end
            test tmath.isapprox(&C, &Cref, 0)
        end
    end

end --T


for _,T in ipairs{cint, cfloat, cdouble, cfloat128} do

    local SMatrix2x2 = sarray.StaticMatrix(T, {2, 2})
    local SMatrix3x2 = sarray.StaticMatrix(T, {3, 2})
    local SMatrix2x3 = sarray.StaticMatrix(T, {2, 3})
    local SVector2 = sarray.StaticVector(T, 2)
    local SVector3 = sarray.StaticVector(T, 3)
    local im = T:unit()

    local Concept = {
        Stack = concepts.Stack(T),
        Vector = concepts.Vector(T),
        Matrix = concepts.Matrix(T),
        Range = concepts.Range
    }

    testenv(T) "Transpose view - Complex - fixed N" do

        terracode
            var A = SMatrix2x3.from({
                {1-2*im,  3-3*im,  5+1*im},
                {2-1*im,  4+2*im,  6-3*im}
            })
            var B = A:transpose()
        end

        --test basic concepts
        test [ Concept.Vector(A.type)]
        test [ Concept.Range(A.type) ]
        --check of transpose type isa Matrix, Vector and Range
        test [ Concept.Matrix(B.type.type)]
        test [ Concept.Vector(B.type.type)]
        test [ Concept.Range(B.type.type) ]

        testset "transpose" do
            terracode
                B(0,0) = -1 --By mutating B we can check that B is a transposed view of A, not a copy
            end
            test B:size(1) == A:size(0) and B:size(0) == A:size(1)
            for i = 0, 1 do
                for j = 0, 2 do
                    test B(j, i) == tmath.conj(A(i, j))
                end
            end
        end

        testset "transpose of transpose" do
            terracode
                var C = B:transpose()
            end
            test C:size(0) == A:size(0) and C:size(1) == A:size(1)
            test tmath.isapprox(&A, C, 0)
        end

    end

    testenv(T) "GEMV - Complex - fixed N" do

        terracode
            var A = SMatrix2x3.from({
                {1-2*im,  3-3*im,  5+1*im},
                {2-1*im,  4+2*im,  6-3*im}
            })
        end

        testset "gemv" do
            terracode
                var x = SVector3.from{1-im, -1+im, 2 -2*im}
                var y = SVector2.zeros()
                var yref = SVector2.from{11 - 5*im, 1 - 19*im}
                matrix.gemv(T(1), &A, &x, T(0), &y)
            end
            test tmath.isapprox(&y, &yref, 0)
        end

        testset "gemv - conjugate transpose A" do
            terracode
                var x = SVector2.from{1-im, -1+im}
                var y = SVector3.zeros()
                var yref = SVector3.from{2*im, 4+6*im, -5-3*im}
                matrix.gemv(T(1), A:transpose(), &x, T(0), &y)
            end
            test tmath.isapprox(&y, &yref, 0)
        end

    end

    testenv(T) "GEMM - Complex - fixed N" do

        terracode
            var A = SMatrix2x2.from({{1 + im, 2 - im}, {3 + 2*im, 4- 3*im}})
            var B = SMatrix2x2.from({{2 + 2*im, -1 + im}, {-1 - im, 2 + 3*im}})
            var C = SMatrix2x2.zeros()
        end

        testset "gemm" do
            terracode
                matrix.gemm([T](1), &A, &B, T(0), &C)
                var Cref = SMatrix2x2.from({{-3+3*im,   5+4*im}, {-5+9*im,  12+7*im}})
            end
            test tmath.isapprox(&C, &Cref, 0)
        end

        testset "gemm - transpose A" do
            terracode
                matrix.gemm([T](1), A:transpose(), &B, T(0), &C)
                var Cref = SMatrix2x2.from({{-1-1*im, 12+7*im}, {1-1*im,  -4+19*im}})
            end
            test tmath.isapprox(&C, &Cref, 0)
        end

        testset "gemm - transpose B" do
            terracode
                matrix.gemm([T](1), &A, B:transpose(), T(0), &C)
                var Cref = SMatrix2x2.from({{1-1*im,  -1-8*im}, {3-3*im,  -6-17*im}})
            end
            test tmath.isapprox(&C, &Cref, 0)
        end

        testset "gemm - transpose A, transpose B" do
            terracode
                matrix.gemm([T](1), A:transpose(), B:transpose(), T(0), &C)
                var Cref = SMatrix2x2.from({{-5-5*im,   0-11*im}, {5-9*im,  14-5*im}})
            end
            test tmath.isapprox(&C, &Cref, 0)
        end

    end

end --T
