-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local base = require("base")
local concepts = require("concepts")
local paramlist = require("concept-parametrized").paramlist

import "terraform"
import "terratest@v1/terratest"

local Any = concepts.Any
local String = concepts.String
local Primitive = concepts.Primitive
local Float = concepts.Float
local NFloat = concepts.NFloat
local Integer = concepts.Integer
local SignedInteger = concepts.SignedInteger
local UnsignedInteger = concepts.UnsignedInteger
local Real = concepts.Real
local BLASFloat = concepts.BLASFloat
local Number = concepts.Number
local Complex = concepts.Complex
local BLASNumber = concepts.BLASNumber

local ComplexOverField = concepts.ComplexOverField


testenv "Concrete concepts" do

	local signed = terralib.newlist{int8, int16, int32, int64}
	local unsigned = terralib.newlist{uint8, uint16, uint32, uint64}
	local floats = terralib.newlist{float, double}
	local otherprimitives = terralib.newlist{bool, rawstring}

	local primitivenumbers = terralib.newlist()
	primitivenumbers:insertall(signed)
	primitivenumbers:insertall(unsigned)
	primitivenumbers:insertall(floats)

	local primitives = terralib.newlist()
	primitives:insertall(primitivenumbers)
	primitives:insertall(otherprimitives)

	testset "Real number hierarchy" do
		test [Number(Number)]
		test [Number(BLASNumber)]
		test [Number(Real) and not Real(Number)]
		test [Real(Integer) and not Integer(Real)]
		test [Integer(UnsignedInteger) and not UnsignedInteger(Integer)]
		test [Integer(SignedInteger) and not SignedInteger(Integer)]
		test [Real(Float) and not Float(Real)]
		test [Float(BLASFloat) and not BLASFloat(FLoat)]
		test [Float(NFloat) and not NFloat(Float)]
	end

	local ComplexInteger = ComplexOverField(Integer)
	local ComplexSignedInteger = ComplexOverField(SignedInteger)
	local ComplexFloat = ComplexOverField(Float)
	local ComplexBLASFloat = ComplexOverField(BLASFloat)
	local ComplexNFloat = ComplexOverField(NFloat)
	
	testset "Complex number hierarchy" do
		test [Number(Complex) and not Complex(Number)]
		test [Complex(ComplexInteger) and not ComplexInteger(Complex)]
		test [ComplexInteger(ComplexSignedInteger) and not ComplexSignedInteger(ComplexInteger)]
		test [Complex(ComplexFloat) and not ComplexFloat(Complex)]
		test [ComplexFloat(ComplexBLASFloat) and not ComplexBLASFloat(ComplexFloat)]
		test [Complex(ComplexBLASFloat) and not ComplexBLASFloat(Complex)]
		test [ComplexFloat(ComplexNFloat) and not ComplexNFloat(ComplexFloat)]
	end

    testset "Floats" do
		test [Float(Float)]
        test [Number(double)]
		test [Number(float)]
        test [Float(double)]
		test [Float(float)]
		test [BLASFloat(double)]
		test [BLASFloat(float)]
        test [concepts.is_specialized_over(Float, Float)]
        test [Float(int32) == false]
        test [Float(rawstring) == false]
		test [Float(Integer) ==  false]
    end

    testset "Integers" do
        --abstract signed/unsigned integers
        test [concepts.is_specialized_over(Integer, Integer)]
		test [concepts.is_specialized_over(Integer, Integer)]
		test [concepts.is_specialized_over(SignedInteger, Integer)]
		test [concepts.is_specialized_over(UnsignedInteger, Integer)]
		--concrete signed integers
       	for _,T in ipairs(signed) do
			test [Integer(T)]
			test [SignedInteger(T)]
			test [UnsignedInteger(T) == false]
		end
		--concrete unsigned integers
       	for _,T in ipairs(unsigned) do
			test [Integer(T)]
			test [SignedInteger(T) == false]
			test [UnsignedInteger(T)]
		end
		--sanity check
       	test [Integer(float) == false]
        test [Integer(rawstring) == false]
    end

    testset "Real numbers" do
        test [concepts.is_specialized_over(Integer, Real)]
		test [concepts.is_specialized_over(Float, Real)]
		for _,T in ipairs(primitivenumbers) do
			test [Real(T)]
		end
    end

    testset "Numbers" do
        test [concepts.is_specialized_over(Real, Number)]
		test [concepts.is_specialized_over(Integer, Number)]
		for _,T in ipairs(primitivenumbers) do
			test [Number(T)]
		end
        test [Number(rawstring) == false]
    end

    testset "Primitive" do
		for _,T in ipairs(primitives) do
			test [Primitive(T)]
		end
    end

	testset "Raw strings" do
		test [String(rawstring)]
		test [String(&uint) == false]
        test [String(Primitive) == false]
	end

	testset "Empty abstract interface" do
		local struct EmptyInterface(concepts.Base) {}
		test [concepts.isconcept(EmptyInterface)]
	end

	testset "Abstract interface" do
		local struct SimpleInterface(concepts.Base) {}
		SimpleInterface.methods.cast = {&SimpleInterface, Integer} -> concepts.Real
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
		terra W:axpy(x: float, v: &W): {} end
		test [Vec(W)]

		local struct WT {}
		terraform WT:axpy(x: float, v: &WT) end
		test [Vec(WT)]

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
		Vec3.methods.dot = concepts.methodtag
		Vec3.methods.axpy = {&Vec3, concepts.Real, &Vec3} -> {}

		local struct F(base.AbstractBase) {}
		terraform F:axpy(a: int8, x: &float)
		end
		terraform F:axpy(a: I, x: &V) where {I: concepts.Real, V: Vec3}
		end
		terraform F:dot(x: &V) where {V: Vec3} end
		test[Vec3(F)]

		local struct E(base.AbstractBase) {}
		terraform E:axpy(x: float)
		end
		terra E:dot() end
		test [Vec3(E) == false]
	end

	testset "Overloaded terra function" do
		local struct A(concepts.Base) {}
		A.methods.size = {&A} -> {concepts.Integral}

		local struct B(concepts.Base) {}
		B.methods.size = {&B, concepts.Integral} -> {concepts.Integral}

		local struct C(concepts.Base) {}
		C.methods.size = {&C, Float, concepts.Integral} -> {concepts.Integral}

		local struct hassize{}

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
			Self.traits.eltype = BLASNumber
		end

		local struct MyConcreteVector(base.AbstractBase) {}
		MyConcreteVector.traits.eltype = float

		local MyVectorNumber = MyVector(Number)

		test [MyVectorNumber(MySpecialVector)]
		test [MyVectorNumber(MyConcreteVector)]
		test [MySpecialVector(MyConcreteVector)]
	end

	testset "Traits with friends" do
		local struct S(base.AbstractBase) {}
		concept A
			Self.traits.iscool = true
			Self:addfriend(S)
		end
		local struct T(base.AbstractBase) {}
		T.traits.iscool = true

		test [A(T)]
		-- If A is not a collection, friends are a short cut for concept checks
		test [A(S)]
	end

	testset "Entries" do
		local struct Ent(concepts.Base) {
			x: Float
			y: Integer
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
		C:addentry("x", Float)
		C:addentry("n", Integer)
		C:addentry("a", String)
		C:addtrait("super_important")
		C:addmetamethod("__apply")
		C:addmethod("scale", {&C, Float} -> {})
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
	Stack:adddefinition{[paramlist.new({Any}, {1}, {0})] = (
			function(C, T)
			    C.methods.length = {&C} -> Integer
			    C.methods.get = {&C, Integer} -> T
			    C.methods.set = {&C, Integer , T} -> {}
			end
		)
	}
	test [concepts.isparametrizedconcept(Stack) == true]

	local Vector = concepts.parametrizedconcept("Vector")
	Vector:adddefinition{[paramlist.new({Any}, {1}, {0})] = (
			function(C, T)
			    local S = Stack(T)
			    C:inherit(S)
			    C.methods.swap = {&C, &S} -> {}
			    C.methods.copy = {&C, &S} -> {}
			end
		)
	}

	local Number = Number
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

	Vector:adddefinition{[paramlist.new({Float}, {1}, {0})] = (
			function(C, T)
			    C.methods.norm = {&C} -> T
			end
		)
	}
	test [concepts.isparametrizedconcept(Vector) == true]

	testset "Dispatch on Any" do
		local S = Stack(Any)
		local V = Vector(Any)
		test [S(V) == true]
		test [V(S) == false]
		test [concepts.is_specialized_over(&V, &S)]
	end

	testset "Dispatch on Integers" do
		local S = Stack(Integer)
		local V1 = Vector(Any)
		local V2 = Vector(Integer)

		test [S(V2) == true]
		test [S(V1) == false]
		test [V2(S) == false]
		test [V1(V2) == true]
		test [V2(V1) == false]
		test [concepts.is_specialized_over(&V2, &V1)]
	end

	testset "Dispatch on Float" do
		local S = Stack(Float)
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
		local Any = Any
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

		local Generic = Matrix(Float, Integer)
		local Special = Matrix(Float, Float)

		test [Generic(Special) == true]
		test [Special(Generic) == false]
	end

	testset "Multipe inheritance" do
		local SVec = concepts.parametrizedconcept("SVec")
		SVec:adddefinition{[paramlist.new({}, {}, {})] = function(S)
				S.traits.length = concepts.traittag
				S.methods.length = &S -> Integer
			end
		}
		SVec:adddefinition{[paramlist.new({Number}, {1}, {0})] = (
				function(S, T)
					S.methods.axpy = {&S, T, &S} -> {}
				end
			)
		}
		SVec:adddefinition{
			[paramlist.new({Float, 3}, {1, 2}, {0, 0})] = (
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

		local SVec3D = SVec(Float, 3)
		test [SVec3D(G) == false]
		test [SVec3D(I) == false]
		test [SVec3D(D) == true]
		test [SVec3D(E) == false]
	end

	testset "Parametrized types" do

	end
end
