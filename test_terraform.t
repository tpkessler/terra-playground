-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"

local io = terralib.includec("stdio.h")
local base = require("base")
local concepts = require("concepts")
local alloc = require('alloc')
local dvector = require("dvector")
local size_t = uint64

local Any = concepts.Any
local Integer = concepts.Integer
local Float = concepts.Float
local Real = concepts.Real
local Number = concepts.Number

import "terratest/terratest"

testenv "terraforming free functions" do

    testset "no args" do
        terraform foo()
            return 2
        end
        test foo() == 2
    end

    testset "concrete types" do
        terraform foo(a : double, b : double)
            return a * b + 2
        end
        terraform foo(a : float, b : double)
            return a * b + 3
        end
        test foo(1., 2.) == 4.0
        test foo(float(1), 2.) == 5.0
    end
    
    testset "global method dispatch parametric concrete types" do
        terraform foo(a : T, b : T) where {T : Real}
            return a * b
        end
        terraform foo(a : int, b : T) where {T : Real}
            return a * b + 1
        end
        terraform foo(a : T, b : int) where {T : Real}
            return a * b + 2
        end
        terraform foo(a : int, b : int)
            return a * b + 3
        end
        --typical use-case in dispatch
        test foo(1., 2.) == 2.0
        test foo(1, 2.) == 3.0
        test foo(1., 2) == 4.0
        test foo(1, 2) == 5.0
    end

    testset "lobal method dispatch parametric concrete types" do
        local terraform foo(a : T, b : T) where {T : Real}
            return a * b
        end
        local terraform foo(a : int, b : T) where {T : Real}
            return a * b + 1
        end
        local terraform foo(a : T, b : int) where {T : Real}
            return a * b + 2
        end
        local terraform foo(a : int, b : int)
            return a * b + 3
        end
        --typical use-case in dispatch
        test foo(1., 2.) == 2.0
        test foo(1, 2.) == 3.0
        test foo(1., 2) == 4.0
        test foo(1, 2) == 5.0
    end

    testset "global method dispatch parametric reference types" do
        terraform foo(a : &T, b : &T) where {T : Real}
            return @a * @b
        end
        terraform foo(a : &int, b : &T) where {T : Real}
            return @a * @b + 1
        end
        terraform foo(a : &T, b : &int) where {T : Real}
            return @a * @b + 2
        end
        terraform foo(a : &int, b : &int)
            return @a * @b + 3
        end
        terracode
            var x = 1.
            var y = 2.
            var i = 1
            var j = 2
        end
        test foo(&x, &y) == 2.0
        test foo(&i, &y) == 3.0
        test foo(&x, &j) == 4.0
        test foo(&i, &j) == 5.0
    end

    testset "global method dispatch mixed parametric concrete/reference types" do
        terraform foo(a : T, b : &T) where {T : Real}
            return a + @b
        end
        terraform foo(a : &T, b : T) where {T : Real}
            return @a + b + 1
        end
        terracode
            var x = 1.
            var y = 2.
        end
        test foo(x, &y) == 3.0
        test foo(&x, y) == 4.0
    end

    testset "local method dispatch parametric reference types" do
        local terraform foo(a : &T, b : &T) where {T : Real}
            return @a * @b
        end
        local terraform foo(a : &int, b : &T) where {T : Real}
            return @a * @b + 1
        end
        local terraform foo(a : &T, b : &int) where {T : Real}
            return @a * @b + 2
        end
        local terraform foo(a : &int, b : &int)
            return @a * @b + 3
        end
        terracode
            var x = 1.
            var y = 2.
            var i = 1
            var j = 2
        end
        test foo(&x, &y) == 2.0
        test foo(&i, &y) == 3.0
        test foo(&x, &j) == 4.0
        test foo(&i, &j) == 5.0
    end

    testset "nested reference types" do
        terraform foo(a : &&T, b : &&T) where {T : Real}
            return @(@a) * @(@b)
        end
        terraform foo(a : &&int, b : &&T) where {T : Real}
            return @(@a) * @(@b) + 1
        end
        terraform foo(a : &&T, b : &&int) where {T : Real}
            return @(@a) * @(@b) + 2
        end
        terraform foo(a : &&int, b : &&int)
            return @(@a) * @(@b) + 3
        end
        terracode
            var x, y, i, j = 1., 2., 1, 2
            var rx, ry, ri, rj = &x, &y, &i, &j
        end
        test foo(&rx, &ry) == 2.0
        test foo(&ri, &ry) == 3.0
        test foo(&rx, &rj) == 4.0
        test foo(&ri, &rj) == 5.0
    end

    testset "duck-typing" do
        terraform foo(a, b)
            return a * b + 1
        end
        terraform foo(a, b, c : T) where {T : Integer}
            return a * b + c
        end
        test foo(2, 3) == 7
        test foo(2, 3, 2) == 8
    end

    testset "varargs" do
        terraform foo(a : int)
            return a + 1
        end
        terraform foo(args ...)
            var res = 1
            escape
                for i,v in ipairs(args.type.entries) do
                    local s = "_" .. tostring(i-1)
                    emit quote
                        res = res * args.[s] 
                    end
                end
            end
            return res
        end
        test foo(2) == 3
        test foo(2, 3) == 6
        test foo(2, 3, 4) == 24
    end

    testset "nearly ambiguous calls" do
        --foo<T>
        terraform foo(a : T, b : T) where {T : Float}
            return a * b
        end
        --foo<T1,T2>
        terraform foo(a : T1, b : T2) where {T1 : Float, T2 : Float}
            return a * b + 1
        end
        --both of the following calls satisfy the concepts dispatch 
        --checks on all arguments. 
        test foo(1., 2.) == 2.0 --calling foo<T> and foo<T1,T2> are both valid. However,
        --foo<T> is considered to be more specialized, so we pick this method.
        test foo(float(1), 2.) == 3.0 --calling foo<T> would lead to a cast, which is 
        --not allowed, so we call foo<T1,T2>
    end

    testset "reference to local typealiases" do
        terraform foo(a : size_t)
            return a + 2
        end
        test foo(size_t(2)) == 4.0
    end    

    testset "nested namespaces" do
        local ns = {}
        ns.Float = Float
        ns.bar = {}
        ns.bar.Float = Float
        --foo<T>
        terraform ns.bar.foo(a : T, b : T) where {T : ns.bar.Float}
            return a * b
        end
        --foo<T1,T2>
        terraform ns.bar.foo(a : T1, b : T2) where {T1 : ns.Float, T2 : ns.bar.Float}
            return a * b + 1
        end
        test ns.bar.foo(1., 2.) == 2.0
        test ns.bar.foo(float(1), 2.) == 3.0 
    end

    testset "Access to parametric types in escape" do
        terraform foo(a : T1, b : T2) where {T1 : Float, T2 : Float}
            escape
                assert(T1 == double and T2 == float)
            end
            return a * b + 1
        end
        test foo(2.0, float(3.0)) == 7
    end

end

testenv "terraforming class methods" do

    --dummy struct
    local struct bar{
        index : int
    }

    terracode
        var mybar = bar{1}
    end

    testset "no args" do
        terraform bar:foo()
            return 2
        end
        test mybar:foo() == 2
    end

    testset "duck-typing" do
        terraform bar:foo(a, b)
            return a * b + self.index
        end
        terraform bar:foo(a, b, c : T) where {T : Integer}
            return a * b + c + self.index
        end
        test mybar:foo(2, 3) == 7
        test mybar:foo(2, 3, 2) == 9
    end

    testset "varargs" do
        terraform bar:foo(a : int)
            return a + self.index
        end
        terraform bar:foo(args ...)
            var res = self.index
            escape
                for i,v in ipairs(args.type.entries) do
                    local s = "_" .. tostring(i-1)
                    emit quote
                        res = res * args.[s] 
                    end
                end
            end
            return res
        end
        test mybar:foo(2) == 3
        test mybar:foo(2, 3) == 6
        test mybar:foo(2, 3, 4) == 24
    end

    testset "static methods" do
        terraform bar.sin(a : T) where {T : Real}
            return a + 2
        end
        terraform bar:foo(a : T) where {T : Real}
            return a + self.index
        end
        terraform bar.sin(a : T, b ...) where {T : Real}
            return a + b._0 + 2
        end
        test bar.sin(2) == 4
        test mybar:foo(2) == 3
        test bar.sin(2,3) == 7
    end

    testset "concrete types" do
        terraform bar:foo(a : double, b : double)
            return a * b + self.index
        end
        terraform bar:foo(a : float, b : double)
            return a * b + self.index + 1
        end
        test mybar:foo(1., 2.) == 3.0
        test mybar:foo(float(1), 2.) == 4.0
    end

    testset "method dispatch parametric concrete types" do
        terraform bar:foo(a : T, b : T) where {T : Real}
            return a * b + self.index
        end
        terraform bar:foo(a : int, b : T) where {T : Real}
            return a * b + 1 + self.index
        end
        terraform bar:foo(a : T, b : int) where {T : Real}
            return a * b + 2 + self.index
        end
        terraform bar:foo(a : int, b : int)
            return a * b + 3 + self.index
        end
        --typical use-case in dispatch
        test mybar:foo(1., 2.) == 3.0
        test mybar:foo(1, 2.) == 4.0
        test mybar:foo(1., 2) == 5.0
        test mybar:foo(1, 2) == 6.0
    end

    testset "method dispatch parametric reference types" do
        terraform bar:foo(a : &T, b : &T) where {T : Real}
            return @a * @b + self.index
        end
        terraform bar:foo(a : &int, b : &T) where {T : Real}
            return @a * @b + 1 + self.index
        end
        terraform bar:foo(a : &T, b : &int) where {T : Real}
            return @a * @b + 2 + self.index
        end
        terraform bar:foo(a : &int, b : &int)
            return @a * @b + 3 + self.index
        end
        terracode
            var x = 1.
            var y = 2.
            var i = 1
            var j = 2
        end
        test mybar:foo(&x, &y) == 3.0
        test mybar:foo(&i, &y) == 4.0
        test mybar:foo(&x, &j) == 5.0
        test mybar:foo(&i, &j) == 6.0
    end

    testset "method dispatch mixed parametric concrete/reference types" do
        terraform bar:foo(a : T, b : &T) where {T : Real}
            return a + @b + self.index
        end
        terraform bar:foo(a : &T, b : T) where {T : Real}
            return @a + b + 1 + self.index
        end
        terracode
            var x = 1.
            var y = 2.
        end
        test mybar:foo(x, &y) == 4.0
        test mybar:foo(&x, y) == 5.0
    end

    testset "nested reference types" do
        terraform bar:foo(a : &&T, b : &&T) where {T : Real}
            return @(@a) * @(@b) + self.index
        end
        terraform bar:foo(a : &&int, b : &&T) where {T : Real}
            return @(@a) * @(@b) + 1 + self.index
        end
        terraform bar:foo(a : &&T, b : &&int) where {T : Real}
            return @(@a) * @(@b) + 2 + self.index
        end
        terraform bar:foo(a : &&int, b : &&int)
            return @(@a) * @(@b) + 3 + self.index
        end
        terracode
            var x, y, i, j = 1., 2., 1, 2
            var rx, ry, ri, rj = &x, &y, &i, &j
        end
        test mybar:foo(&rx, &ry) == 3.0
        test mybar:foo(&ri, &ry) == 4.0
        test mybar:foo(&rx, &rj) == 5.0
        test mybar:foo(&ri, &rj) == 6.0
    end

    testset "nearly ambiguous calls" do
        --foo<T>
        terraform bar:foo(a : T, b : T) where {T : Float}
            return a * b + self.index
        end
        --foo<T1,T2>
        terraform bar:foo(a : T1, b : T2) where {T1 : Float, T2 : Float}
            return a * b + 1 + self.index
        end
        --both of the following calls satisfy the concepts dispatch 
        --checks on all arguments. 
        test mybar:foo(1., 2.) == 3.0 --calling foo<T> and foo<T1,T2> are both valid. However,
        --foo<T> is considered to be more specialized, so we pick this method.
        test mybar:foo(float(1), 2.) == 4.0 --calling foo<T> would lead to a cast, which is 
        --not allowed, so we call foo<T1,T2>
    end

    testset "nested namespaces" do
        local ns = {}
        ns.Float = Float
        ns.sin = {}
        ns.sin.Float = Float
        ns.sin.bar = bar
        --foo<T>
        terraform ns.sin.bar:foo(a : T, b : T) where {T : ns.sin.Float}
            return a * b + self.index
        end
        --foo<T1,T2>
        terraform ns.sin.bar:foo(a : T1, b : T2) where {T1 : ns.Float, T2 : ns.sin.Float}
            return a * b + 1  + self.index
        end
        terracode
            var mybar = ns.sin.bar{1}
        end
        test mybar:foo(1., 2.) == 3.0
        test mybar:foo(float(1), 2.) == 4.0 
    end

    testset "use in parametric class definition" do
        local Bar = function(T)
            local struct bar{
                x : T
            }
            terraform bar:eval(x : S) where {S}
                return x + self.x
            end
            return bar
        end
        local bbar = Bar(double)
        terracode
            var mybar = bbar{1}
        end
        test mybar:eval(1.) == 2
    end

end

testenv "defining regular concepts" do

    concept MyStack
        Self.methods.length = {&Self} -> Integer
        Self.methods.get = {&Self, Integer} -> Any
        Self.methods.set = {&Self, Integer , Any} -> {}
    end

    test [concepts.isconcept(MyStack) == true]

    concept VectorAny
        local S = MyStack
        Self:inherit(S)
        Self.methods.swap = {&Self, &S} -> {}
        Self.methods.copy = {&Self, &S} -> {}
    end

    test [concepts.isconcept(VectorAny) == true]

    concept VectorNumber
        Self:inherit(VectorAny)
        local S = MyStack
        Self.methods.fill = {&Self, Number} -> {}
        Self.methods.clear = {&Self} -> {}
        Self.methods.sum = {&Self} -> Number
        Self.methods.axpy = {&Self, Number, &S} -> {}
        Self.methods.dot = {&Self, &S} -> Number
    end
    
    test [concepts.isconcept(VectorNumber) == true]

    concept VectorFloat
        Self:inherit(VectorNumber)
        Self.methods.norm = {&Self} -> Float
    end

    test [concepts.isconcept(VectorFloat) == true]

    testset "inheritance and specialization" do
        test [VectorAny(MyStack) == false]
        test [concepts.is_specialized_over(&VectorAny, &MyStack)]
        test [MyStack(VectorAny) == true]
        test [MyStack(VectorNumber) == true]
        test [MyStack(VectorFloat) == true]
        test [VectorNumber(MyStack) == false]
        test [VectorAny(VectorNumber) == true]
        test [VectorNumber(VectorAny) == false]
        test [concepts.is_specialized_over(&VectorNumber, &VectorAny)]
        test [VectorFloat(MyStack) == false]
        test [VectorAny(VectorNumber) == true]
        test [VectorAny(VectorFloat) == true]
        test [VectorAny(VectorNumber) == true]
        test [VectorNumber(VectorFloat) == true]
        test [VectorFloat(VectorNumber) == false]
        test [VectorFloat(VectorAny) == false]
        test [concepts.is_specialized_over(&VectorFloat, &VectorNumber)]
    end

end

testenv "defining parametrized concepts" do

    concept MyStack(T) where {T}
        Self.methods.length = {&Self} -> Integer
        Self.methods.get = {&Self, Integer} -> T
        Self.methods.set = {&Self, Integer , T} -> {}
    end

    test [concepts.isparametrizedconcept(MyStack) == true]

    concept Vector(T) where {T}
        local S = MyStack(T)
        Self:inherit(S)
        Self.methods.swap = {&Self, &S} -> {}
        Self.methods.copy = {&Self, &S} -> {}
    end

    concept Vector(T) where {T : Number}
        local S = MyStack(T)
        Self.methods.fill = {&Self, T} -> {}
        Self.methods.clear = {&Self} -> {}
        Self.methods.sum = {&Self} -> T
        Self.methods.axpy = {&Self, T, &S} -> {}
        Self.methods.dot = {&Self, &S} -> T
    end

    concept Vector(T) where {T : Float}
        Self.methods.norm = {&Self} -> T
    end

    test [concepts.isparametrizedconcept(Vector) == true]

    testset "Dispatch on Any" do
        local S = MyStack(concepts.Any)
        local V = Vector(concepts.Any)

        test [S(V) == true]
        test [V(S) == false]
        test [concepts.is_specialized_over(&V, &S)]
    end

    testset "Dispatch on Integers" do
        local S = MyStack(Integer)
        local V1 = Vector(concepts.Any)
        local V2 = Vector(Integer)

        test [S(V2) == true]
        test [S(V1) == false]
        test [V2(S) == false]
        test [V1(V2) == true]
        test [V2(V1) == false]
        test [concepts.is_specialized_over(&V2, &V1)]
    end

    testset "Dispatch on Float" do
        local S = MyStack(Float)
        local V1 = Vector(Any)
        local V2 = Vector(Number)
        local V3 = Vector(Float)

        test [S(V1) == false]
        test [S(V2) == false]
        test [S(V3) == true]
        test [V3(S) == false]
        test [V1(V2) == true]
        test [V1(V3) == true]
        test [V1(V2) == true]
        test [V2(V3) == true]
        test [V3(V2) == false]
        test [V3(V1) == false]
        test [concepts.is_specialized_over(&V3, &V2)]
    end

    testset "Compile-time integer and string dispatch" do
        local A = concepts.newconcept("A")
        A.traits.isfoo = "A"
        local B = concepts.newconcept("B")
        B.traits.isfoo = "B"
        local C = concepts.newconcept("C")
        C.traits.isfoo = "C"

        concept Foo(N) where {N : 1}
            assert(N == 1)
            Self:inherit(A)
        end

        concept Foo(N) where {N : 2}
            assert(N == 2)
            Self:inherit(B)
        end

        concept Foo(N) where {N : 3}
            assert(N == 3)
            Self:inherit(C)
        end

        concept Foo(S) where {S : "hello"}
            assert(S == "hello")
            Self.traits.isfoo = S
        end

        local Foo1 = Foo(1)
        local Foo2 = Foo(2)
        local Foo3 = Foo(3)
        local Foo4 = Foo("hello")
        test [A(Foo1) == true]
        test [Foo1(A) == true]

        test [B(Foo2) == true]
        test [Foo2(B) == true]
        test [A(B) == false]
        test [B(A) == false]

        test [C(Foo3) == true]
        test [Foo3(C) == true]
        test [C(A) == false]
        test [C(B) == false]
        test [A(C) == false]
        test [B(C) == false]

        test [Foo4.traits.isfoo == "hello"]
    end

    testset "Multiple Arguments" do

        concept Matrix(T1, T2) where {T1 : Any, T2 : Any}
            Self.methods.sum = {&Self} -> {}
        end

        concept Matrix(T, T) where {T : Any}
            Self.methods.special_sum = {&Self} -> {}
        end

		local Generic = Matrix(concepts.Float, Integer)
		local Special = Matrix(concepts.Float, concepts.Float)

		test [Generic(Special) == true]
		test [Special(Generic) == false]
	end

    testset "Multipe inheritance" do
		local SVec = concepts.parametrizedconcept("SVec")

        concept SVec()
            Self.traits.length = concepts.traittag
			Self.methods.length = &Self -> Integer
        end

        concept SVec(T) where {T : concepts.Number}
			Self.methods.axpy = {&Self, T, &Self} -> {}
        end

        concept SVec(T, N) where {T: concepts.Float, N: concepts.Value}
            assert(type(N) == "number")
			Self.traits.length = N
        end

        concept SVec(T, N) where {T : concepts.Float, N : 3}
			assert(N == 3)
			Self.methods.cross = {&Self, &Self} -> T
        end

		local struct H(base.AbstractBase) {}
		H.methods.length = &H -> int32

		local struct G(base.AbstractBase) {}
		G.traits.length = 2
		G.methods.length = &G -> int64

		local SVecAny = SVec()
		test [SVecAny(H) == false]
		test [SVecAny(G) == true]

		local struct I(base.AbstractBase) {}
		I.traits.length = 2
		I.methods.length = &I -> uint64
		I.methods.axpy = {&I, int32, &I} -> {}

		local SVecInt = SVec(Integer)
		test [SVecInt(G) == false]
		test [SVecInt(I) == true]

		local struct D(base.AbstractBase) {}
		D.traits.length = 3
		D.methods.length = &D -> uint64
		D.methods.axpy = {&D, double, &D} -> {}
		D.methods.cross = {&D, &D} -> {}

		local struct D(base.AbstractBase) {}
		D.traits.length = 3
		D.methods.length = &D -> uint64
		D.methods.axpy = {&D, double, &D} -> {}
		D.methods.cross = {&D, &D} -> {}

		local struct E(base.AbstractBase) {}
		E.traits.length = 4
		E.methods.length = &E -> uint64
		E.methods.axpy = {&E, double, &E} -> {}
		E.methods.cross = {&E, &E} -> {}

		local SVec3D = SVec(concepts.Float, 3)
		test [SVec3D(G) == false]
		test [SVec3D(I) == false]
		test [SVec3D(D) == true]
		test [SVec3D(E) == false]
	end
end
