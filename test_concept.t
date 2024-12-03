-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local base = require("base")
local concept = require("concept")
local paramlist = require("concept-parametrized").paramlist

import "terratest/terratest"
import "terraform"

testenv "Collections" do

    testset "Floats" do
        --concrete float
        test [concept.Float64(double)]
        test [concept.Float64(float) == false]
        test [concept.is_specialized_over(concept.Float64, concept.Float64)]
        --abstract floats
        test [concept.Float(double)]
        test [concept.Float(float)]
        test [concept.is_specialized_over(concept.Float, concept.Float)]
        test [concept.Float(int32) == false]
        test [concept.Float(rawstring) == false]
    end

    testset "Integers" do
        --concrete integers
        test [concept.Int32(int32)]
        test [concept.Int32(int)]
        test [concept.Int32(int16) == false]
        test [concept.is_specialized_over(concept.Int32, concept.Int32)]
        --abstract signed integers
        test [concept.is_specialized_over(concept.Integer, concept.Integer)]
        test [concept.Integer(int)]
        test [concept.Integer(int32)]
        test [concept.Integer(int64)]
        test [concept.Integer(uint) == false]
        test [concept.Integer(float) == false]
        test [concept.Integer(rawstring) == false]
		-- abstract integers
        test [concept.is_specialized_over(concept.Integral, concept.Integral)]
        test [concept.Integral(int)]
        test [concept.Integral(int32)]
        test [concept.Integral(int64)]
        test [concept.Integral(uint)]
        test [concept.Integral(uint64)]
        test [concept.Integral(float) == false]
        test [concept.Integral(rawstring) == false]
    end

    testset "Real numbers" do
        test [concept.is_specialized_over(concept.Integer, concept.Real)]
        test [concept.Real(int32)]
        test [concept.Real(int64)]
        test [concept.is_specialized_over(concept.Float, concept.Real)]
        test [concept.Real(float)]
        test [concept.Real(double)]
        test [concept.Real(uint) == false]
    end

    testset "Numbers" do
        test [concept.is_specialized_over(concept.Real, concept.Number)]
        test [concept.Number(int32)]
        test [concept.Number(float)]
        test [concept.Number(rawstring) == false]      
    end

	testset "Raw strings" do
		test [concept.RawString(rawstring)]
		test [concept.RawString(&uint) == false]
        test [concept.is_specialized_over(concept.RawString, concept.Primitive) == false]
		test [concept.RawString(concept.Primitive) == false]
	end

	testset "Empty abstract interface" do
		local struct EmptyInterface(concept.Base) {}
		test [concept.isconcept(EmptyInterface)]
	end

	testset "Abstract interface" do
		local struct SimpleInterface(concept.Base) {}
		SimpleInterface.methods.cast = {&SimpleInterface, concept.Integer} -> concept.Real
		test [concept.isconcept(SimpleInterface)]
		
		local struct B {}
		terra B:cast(x: int8) : float end
		test [SimpleInterface(B)]
	end

	testset "Self-referencing interface on methods" do
		local struct Vec(concept.Base) {}
		test [concept.isconcept(Vec)]
		Vec.methods.axpy = {&Vec, concept.Real, &Vec} -> {}

		local struct V {}
		terra V:axpy(x: double, v: &V): {} end
		test [Vec(V)]

		local struct W {}
		terra W:axpy(x: float, v: &V): {} end
		test [Vec(W)]

		local struct Z {}
		terra Z:axpy(x: float, v: &int): {} end
		test [Vec(Z) == false]

		local struct U {}
		terra U:axpy(x: float, v: &Z): {} end
		test [Vec(U) == false]

		local struct P {}
		terra P:axpy(x: float, v: V): {} end
		test [Vec(P) == false]
	end

	testset "Self-referencing interface on terraform methods" do
		local struct Vec3(concept.Base) {}
		test [concept.isconcept(Vec3)]
		Vec3.methods.axpy = {&Vec3, concept.Real, &Vec3} -> {}

		local struct F(base.AbstractBase) {}
		terraform F:axpy(a: I, x: &F) where {I: concept.Int8, F: concept.Float32}
		end
		terraform F:axpy(a: I, x: &V) where {I: concept.Real, V: Vec3}
		end
		test[Vec3(F)]

		local struct E(base.AbstractBase) {}
		terraform E:axpy(x: float)
		end
		test [Vec3(E) == false]
	end

	testset "Traits - unconstrained" do
		local struct Trai(concept.Base) {}
		Trai.traits.iscool = concept.traittag
		test [concept.isconcept(Trai)]

		local struct T1(base.AbstractBase) {}
		T1.traits.iscool = true
		test [Trai(T1)]

		local struct T2(base.AbstractBase) {}
		T2.traits.iscool = false
		test [Trai(T2)]
	end

	testset "Traits - constrained" do
		local struct Trai(concept.Base) {}
		Trai.traits.elsize = 10
		test [concept.isconcept(Trai)]

		local struct T1(base.AbstractBase) {}
		T1.traits.elsize = 10
		test [Trai(T1)]

		local struct T2(base.AbstractBase) {}
		T2.traits.elsize = 20
		test [Trai(T2) == false]
	end

	testset "Entries" do
		local struct Ent(concept.Base) {
			x: concept.Float
			y: concept.Integer
		}
		test [concept.isconcept(Ent)]

		local struct T1(base.AbstractBase) {
			x: double
			y: int8
			z: rawstring
		}
		test [Ent(T1)]

		local struct T2(base.AbstractBase) {
			x: int
			y: int8
		}
		test [Ent(T2) == false]
	end

	testset "Full Example" do
		local C = concept.newconcept("C")
		C:addentry("x", concept.Float)
		C:addentry("n", concept.Integral)
		C:addentry("a", concept.RawString)
		C:addtrait("super_important")
		C:addmetamethod("__apply")
		C:addmethod("scale", {&C, concept.Float} -> {})
		test [concept.isconcept(C)]

		local struct T1(base.AbstractBase) {
			x: float
			n: uint64
			a: rawstring
		}
		T1.traits.super_important = 3.14
		terra T1.metamethods.__apply(self: &T1, x: float) end
		terra T1:scale(a: float) end
		test [C(T1)]
	end
end

testenv "Parametrized Concepts" do
	local Stack = concept.parametrizedconcept("Stack")
	Stack[paramlist.new({concept.Any}, {1}, {0})] = function(C, T)
	    C.methods.length = {&C} -> concept.Integral
	    C.methods.get = {&C, concept.Integral} -> T
	    C.methods.set = {&C, concept.Integral , T} -> {}
	end
	test [concept.isparametrizedconcept(Stack) == true]

	local Vector = concept.parametrizedconcept("Vector")
	Vector[paramlist.new({concept.Any}, {1}, {0})] = function(C, T)
	    local S = Stack(T)
	    C:inherit(S)
	    C.methods.swap = {&C, &S} -> {}
	    C.methods.copy = {&C, &S} -> {}
	end

	local Number = concept.Number
	Vector[paramlist.new({Number}, {1}, {0})] = function(C, T)
	    local S = Stack(T)
	    C.methods.fill = {&C, T} -> {}
	    C.methods.clear = {&C} -> {}
	    C.methods.sum = {&C} -> T
	    C.methods.axpy = {&C, T, &S} -> {}
	    C.methods.dot = {&C, &S} -> T
	end

	Vector[paramlist.new({concept.Float}, {1}, {0})] = function(C, T)
	    C.methods.norm = {&C} -> T
	end
	test [concept.isparametrizedconcept(Vector) == true]
	testset "Dispatch on Any" do
		local S = Stack(concept.Any)
		local V = Vector(concept.Any)

		test [S(V) == true]
		test [V(S) == false]
		test [concept.is_specialized_over(&V, &S)]
	end

	testset "Dispatch on Integers" do
		local S = Stack(concept.Integer)
		local V1 = Vector(concept.Any)
		local V2 = Vector(concept.Integer)

		test [S(V2) == true]
		test [S(V1) == false]
		test [V2(S) == false]
		test [V1(V2) == true]
		test [V2(V1) == false]
		test [concept.is_specialized_over(&V2, &V1)]
	end

	testset "Dispatch on Float" do
		local S = Stack(concept.Float)
		local V1 = Vector(concept.Any)
		local V2 = Vector(concept.Number)
		local V3 = Vector(concept.Float)

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
		test [concept.is_specialized_over(&V3, &V2)]
	end

	testset "Compile-time integer and string dispatch" do
		local A = concept.newconcept("A")
		A.traits.isfoo = "A"
		local B = concept.newconcept("B")
		B.traits.isfoo = "B"
		local C = concept.newconcept("C")
		C.traits.isfoo = "C"
		local Foo = concept.parametrizedconcept("Foo")
		Foo[paramlist.new({1}, {1}, {0})] = function(S, N)
			assert(N == 1)
			S:inherit(A)
		end
		Foo[paramlist.new({2}, {1}, {0})] = function(S, N)
			assert(N == 2)
			S:inherit(B)
		end
		Foo[paramlist.new({3}, {1}, {0})] = function(S, N)
			assert(N == 3)
			S:inherit(C)
		end
		Foo[paramlist.new({"hello"}, {1}, {0})] = function(S, H)
			assert(H == "hello")
			S.traits.isfoo = H
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
		local Any = concept.Any
		local Matrix = concept.parametrizedconcept("Matrix")
		Matrix[paramlist.new({Any, Any}, {1, 2}, {0, 0})] = function(C, T1, T2)
			C.methods.sum = {&C} -> {}
		end

		Matrix[paramlist.new({Any}, {1, 1}, {0, 0})] = function(C, T1, T2)
			C.methods.special_sum = {&C} -> {}
		end

		local Generic = Matrix(concept.Float, concept.Integer)
		local Special = Matrix(concept.Float, concept.Float)

		test [Generic(Special) == true]
		test [Special(Generic) == false]
	end

	testset "Multipe inheritance" do
		local SVec = concept.parametrizedconcept("SVec")
		SVec[paramlist.new({}, {}, {})] = function(S)
			S.traits.length = concept.traittag
			S.methods.length = &S -> concept.Integral
		end
		SVec[paramlist.new({concept.Number}, {1}, {0})] = function(S, T)
			S:inherit(SVec())
			S.methods.axpy = {&S, T, &S} -> {}
		end
		SVec[paramlist.new({concept.Float, 3}, {1, 2}, {0, 0})] = function(S, T, N)
			assert(N == 3)
			S:inherit(SVec(T))
			S.traits.length = N
			S.methods.cross = {&S, &S} -> T
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

		local SVecInt = SVec(concept.Integer)
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

		local SVec3D = SVec(concept.Float, 3)
		test [SVec3D(G) == false]
		test [SVec3D(I) == false]
		test [SVec3D(D) == true]
		test [SVec3D(E) == false]
	end
end
