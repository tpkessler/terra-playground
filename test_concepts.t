-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local base = require("base")
local concepts = require("concepts")
local paramlist = require("concept-parametrized").paramlist

import "terratest/terratest"
import "terraform"

testenv "Concrete concepts" do

    testset "Floats" do
        --concrete float
        test [concepts.Float64(double)]
        test [concepts.Float64(float) == false]
        test [concepts.is_specialized_over(concepts.Float64, concepts.Float64)]
        --abstract floats
        test [concepts.Float(double)]
        test [concepts.Float(float)]
        test [concepts.is_specialized_over(concepts.Float, concepts.Float)]
        test [concepts.Float(int32) == false]
        test [concepts.Float(rawstring) == false]
    end

    testset "Integers" do
        --concrete integers
        test [concepts.Int32(int32)]
        test [concepts.Int32(int)]
        test [concepts.Int32(int16) == false]
        test [concepts.is_specialized_over(concepts.Int32, concepts.Int32)]
        --abstract signed integers
        test [concepts.is_specialized_over(concepts.Integer, concepts.Integer)]
        test [concepts.Integer(int)]
        test [concepts.Integer(int32)]
        test [concepts.Integer(int64)]
        test [concepts.Integer(uint) == false]
        test [concepts.Integer(float) == false]
        test [concepts.Integer(rawstring) == false]
		-- abstract integers
        test [concepts.is_specialized_over(concepts.Integral, concepts.Integral)]
        test [concepts.Integral(int)]
        test [concepts.Integral(int32)]
        test [concepts.Integral(int64)]
        test [concepts.Integral(uint)]
        test [concepts.Integral(uint64)]
        test [concepts.Integral(float) == false]
        test [concepts.Integral(rawstring) == false]
    end

    testset "Real numbers" do
        test [concepts.is_specialized_over(concepts.Integer, concepts.Real)]
        test [concepts.Real(int32)]
        test [concepts.Real(int64)]
        test [concepts.is_specialized_over(concepts.Float, concepts.Real)]
        test [concepts.Real(float)]
        test [concepts.Real(double)]
        test [concepts.Real(uint) == false]
    end

    testset "Numbers" do
        test [concepts.is_specialized_over(concepts.Real, concepts.Number)]
        test [concepts.Number(int32)]
        test [concepts.Number(float)]
        test [concepts.Number(rawstring) == false]      
    end

	testset "Raw strings" do
		test [concepts.RawString(rawstring)]
		test [concepts.RawString(&uint) == false]
        test [concepts.is_specialized_over(concepts.RawString, concepts.Primitive) == false]
		test [concepts.RawString(concepts.Primitive) == false]
	end

	testset "Empty abstract interface" do
		local struct EmptyInterface(concepts.Base) {}
		test [concepts.isconcept(EmptyInterface)]
	end

	testset "Abstract interface" do
		local struct SimpleInterface(concepts.Base) {}
		SimpleInterface.methods.cast = {&SimpleInterface, concepts.Integer} -> concepts.Real
		test [concepts.isconcept(SimpleInterface)]
		
		local struct B {}
		terra B:cast(x: int8) : float end
		test [SimpleInterface(B)]
	end

	testset "Self-referencing interface on methods" do
		local struct Vec(concepts.Base) {}
		test [concepts.isconcept(Vec)]
		Vec.methods.axpy = {&Vec, concepts.Real, &Vec} -> {}

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
		local struct Vec3(concepts.Base) {}
		test [concepts.isconcept(Vec3)]
		Vec3.methods.axpy = {&Vec3, concepts.Real, &Vec3} -> {}

		local struct F(base.AbstractBase) {}
		terraform F:axpy(a: I, x: &F) where {I: concepts.Int8, F: concepts.Float32}
		end
		terraform F:axpy(a: I, x: &V) where {I: concepts.Real, V: Vec3}
		end
		test[Vec3(F)]

		local struct E(base.AbstractBase) {}
		terraform E:axpy(x: float)
		end
		test [Vec3(E) == false]
	end

	testset "Overloaded terra function" do
		--concept 1
		local struct A(concepts.Base) {}
		A.methods.size = {&A} -> {concepts.Integral}
		--concept 2
		local struct B(concepts.Base) {}
		B.methods.size = {&B, concepts.Integral} -> {concepts.Integral}
		--concept 3
		local struct C(concepts.Base) {}
		C.methods.size = {&C, concepts.Float, concepts.Integral} -> {concepts.Integral}
		--struct definition
		local struct hassize{}
		--implementation of the size method as an overloaded function
		hassize.methods.size = terralib.overloadedfunction("size",{
			terra(self : &hassize) return 1 end,
			terra(self : &hassize, i : int) return i end
		})
		test [ A(hassize) ]
		test [ B(hassize) ]
		test [ C(hassize) == false ]
	end

	testset "Traits - unconstrained" do
		local struct Trai(concepts.Base) {}
		Trai.traits.iscool = concepts.traittag
		test [concepts.isconcept(Trai)]

		local struct T1(base.AbstractBase) {}
		T1.traits.iscool = true
		test [Trai(T1)]

		local struct T2(base.AbstractBase) {}
		T2.traits.iscool = false
		test [Trai(T2)]
	end

	testset "Traits - constrained" do
		local struct Trai(concepts.Base) {}
		Trai.traits.elsize = 10
		test [concepts.isconcept(Trai)]

		local struct T1(base.AbstractBase) {}
		T1.traits.elsize = 10
		test [Trai(T1)]

		local struct T2(base.AbstractBase) {}
		T2.traits.elsize = 20
		test [Trai(T2) == false]
	end

	testset "Traits - parametrized" do
		concept MyVector(T) where {T}
			Self.traits.eltype = T
		end

		concept MySpecialVector
			Self.traits.eltype = concepts.BLASNumber
		end

		local struct MyConcreteVector(base.AbstractBase) {}
		MyConcreteVector.traits.eltype = float

		local MyVectorNumber = MyVector(concepts.Number)

		test [MyVectorNumber(MySpecialVector)]
		test [MyVectorNumber(MyConcreteVector)]
		test [MySpecialVector(MyConcreteVector)]
	end

	testset "Entries" do
		local struct Ent(concepts.Base) {
			x: concepts.Float
			y: concepts.Integer
		}
		test [concepts.isconcept(Ent)]

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
		local C = concepts.newconcept("C")
		C:addentry("x", concepts.Float)
		C:addentry("n", concepts.Integral)
		C:addentry("a", concepts.RawString)
		C:addtrait("super_important")
		C:addmetamethod("__apply")
		C:addmethod("scale", {&C, concepts.Float} -> {})
		test [concepts.isconcept(C)]

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

testenv "Parametrized concepts" do
	local Stack = concepts.parametrizedconcept("Stack")
	Stack:adddefinition{[paramlist.new({concepts.Any}, {1}, {0})] = (
			function(C, T)
			    C.methods.length = {&C} -> concepts.Integral
			    C.methods.get = {&C, concepts.Integral} -> T
			    C.methods.set = {&C, concepts.Integral , T} -> {}
			end
		)
	}
	test [concepts.isparametrizedconcept(Stack) == true]

	local Vector = concepts.parametrizedconcept("Vector")
	Vector:adddefinition{[paramlist.new({concepts.Any}, {1}, {0})] = (
			function(C, T)
			    local S = Stack(T)
			    C:inherit(S)
			    C.methods.swap = {&C, &S} -> {}
			    C.methods.copy = {&C, &S} -> {}
			end
		)
	}

	local Number = concepts.Number
	Vector:adddefinition{[paramlist.new({Number}, {1}, {0})] = (
		function(C, T)
			    local S = Stack(T)
			    C.methods.fill = {&C, T} -> {}
			    C.methods.clear = {&C} -> {}
			    C.methods.sum = {&C} -> T
			    C.methods.axpy = {&C, T, &S} -> {}
			    C.methods.dot = {&C, &S} -> T
			end
		)
	}

	Vector:adddefinition{[paramlist.new({concepts.Float}, {1}, {0})] = (
			function(C, T)
			    C.methods.norm = {&C} -> T
			end
		)
	}
	test [concepts.isparametrizedconcept(Vector) == true]
	testset "Dispatch on Any" do
		local S = Stack(concepts.Any)
		local V = Vector(concepts.Any)

		test [S(V) == true]
		test [V(S) == false]
		test [concepts.is_specialized_over(&V, &S)]
	end

	testset "Dispatch on Integers" do
		local S = Stack(concepts.Integer)
		local V1 = Vector(concepts.Any)
		local V2 = Vector(concepts.Integer)

		test [S(V2) == true]
		test [S(V1) == false]
		test [V2(S) == false]
		test [V1(V2) == true]
		test [V2(V1) == false]
		test [concepts.is_specialized_over(&V2, &V1)]
	end

	testset "Dispatch on Float" do
		local S = Stack(concepts.Float)
		local V1 = Vector(concepts.Any)
		local V2 = Vector(concepts.Number)
		local V3 = Vector(concepts.Float)

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
		local Foo = concepts.parametrizedconcept("Foo")
		Foo:adddefinition{[paramlist.new({1}, {1}, {0})] = (
				function(S, N)
					assert(N == 1)
					S:inherit(A)
				end
			)
		}
		Foo:adddefinition{[paramlist.new({2}, {1}, {0})] = (
				function(S, N)
					assert(N == 2)
					S:inherit(B)
				end
			)
		}
		Foo:adddefinition{[paramlist.new({3}, {1}, {0})] = (
				function(S, N)
					assert(N == 3)
					S:inherit(C)
				end
			)
		}
		Foo:adddefinition{[paramlist.new({"hello"}, {1}, {0})] = (
				function(S, H)
					assert(H == "hello")
					S.traits.isfoo = H
				end
			)
		}
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
		local Any = concepts.Any
		local Matrix = concepts.parametrizedconcept("Matrix")
		Matrix:adddefinition{[paramlist.new({Any, Any}, {1, 2}, {0, 0})] = (
				function(C, T1, T2)
					C.methods.sum = {&C} -> {}
				end
			)
		}

		Matrix:adddefinition{[paramlist.new({Any}, {1, 1}, {0, 0})] = (
				function(C, T1, T2)
					C.methods.special_sum = {&C} -> {}
				end
			)
		}

		local Generic = Matrix(concepts.Float, concepts.Integer)
		local Special = Matrix(concepts.Float, concepts.Float)

		test [Generic(Special) == true]
		test [Special(Generic) == false]
	end

	testset "Multipe inheritance" do
		local SVec = concepts.parametrizedconcept("SVec")
		SVec:adddefinition{[paramlist.new({}, {}, {})] = function(S)
				S.traits.length = concepts.traittag
				S.methods.length = &S -> concepts.Integral
			end
		}
		SVec:adddefinition{[paramlist.new({concepts.Number}, {1}, {0})] = (
				function(S, T)
					S.methods.axpy = {&S, T, &S} -> {}
				end
			)
		}
		SVec:adddefinition{
			[paramlist.new({concepts.Float, 3}, {1, 2}, {0, 0})] = (
				function(S, T, N)
					assert(N == 3)
					S.traits.length = N
					S.methods.cross = {&S, &S} -> T
				end
			)
		}
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

		local SVecInt = SVec(concepts.Integer)
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
