local concept = require("concept")
local interface = require("interface")
local template = require("template")

local Simple = interface.Interface:new{
	foo = concept.Real -> concept.Number
}
local SimpleC = concept.Concept:from_interface("Simple", Simple)

local struct implSimple {}
implSimple.methods.foo = terra(self: &implSimple, x: concept.Real): concept.Number end

--using test library
import "terratest/terratest"

testenv "concepts" do

    testset "Floats" do
        --concrete float
        test [concept.Float64(double)]
        test [concept.Float64(float) == false]
        test [concept.Float64(concept.Float64)]
        --abstract floats
        test [concept.Float(double)]
        test [concept.Float(float)]
        test [concept.Float(concept.Float)]
        test [concept.Float(int32) == false]
        test [concept.Float(double, double) == false]
        test [concept.Float(rawstring) == false]
    end

    testset "Integers" do
        --concrete integers
        test [concept.Int32(int32)]
        test [concept.Int32(int)]
        test [concept.Int32(int16) == false]
        test [concept.Int32(concept.Int32)]
        --abstract floats
        test [concept.Integer(concept.Integer)]
        test [concept.Integer(int)]
        test [concept.Integer(int32)]
        test [concept.Integer(int64)]
        test [concept.Integer(float) == false]
        test [concept.Integer(int, int) == false]
        test [concept.Integer(rawstring) == false]
    end

    testset "Real numbers" do
        test [concept.Real(concept.Integer)]
        test [concept.Real(int32)]
        test [concept.Real(int64)]
        test [concept.Real(concept.Float)]
        test [concept.Real(float)]
        test [concept.Real(double)]
    end

    testset "Numbers" do
        test [concept.Number(concept.Real)]
        test [concept.Number(int32)]
        test [concept.Number(float)]
        test [concept.Number(rawstring) == false]      
    end

	testset "Concept OR" do
		local C = concept.Int32 + concept.Float32
		test [C(int32)]
		test [C(float)]
		test [C(uint) == false]
		test [C(double) == false]
	end

	testset "Concept AND" do
		local C = concept.Float * concept.Float64
		test [C(double)]
		test [C(float) == false]
	end

	testset "Concept DIV" do
		local C = concept.Number / concept.Integer
		test [C(double)]
		test [C(float)]
		test [C(int32) == false]
		test [C(int64) == false]

	end

	testset "Raw strings" do
		test [concept.RawString(rawstring)]
		test [concept.RawString(&uint) == false]
		test [concept.RawString(concept.Primitive) == false]
	end

	testset "Pointers" do
		test [concept.Pointer(concept.Pointer)]
		test [concept.Pointer(concept.RawString)]
		test [concept.RawString(concept.Pointer) == false]
		test [concept.Pointer(&opaque)]
		test [concept.Pointer(concept.Float) == false]
		test [concept.Pointer(&&int)]
	end

	testset "Empty abstract interface" do
		local EmptyInterface = concept.AbstractInterface:new("Empty")
		test [concept.isconcept(EmptyInterface)]
	end

	testset "Abstract interface" do
		local SimpleInterface = concept.AbstractInterface:new("SimpleAbs")
		test [concept.isconcept(SimpleInterface)]
		
		SimpleInterface:adddefinition{cast = concept.Integer -> concept.Real}
		local struct B {}
		terra B:cast(x: int8): float end
		test [SimpleInterface(B)]
	end

	testset "Self-referencing interface on methods" do
		local Vec = concept.AbstractInterface:new("Vec")
		test [concept.isconcept(Vec)]
		Vec:adddefinition{axpy = {concept.Real, &Vec} -> {}}

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

	testset "Self-referencing interface on templates" do
		local Vec = concept.AbstractInterface:new("Vec")
		test [concept.isconcept(Vec)]
		Vec:adddefinition{axpy = {concept.Real, &Vec} -> {}}

		local struct F {}
		F.templates = {}
		F.templates.axpy = template.Template:new("axpy")
		F.templates.axpy[{concept.Any, concept.Int8, concept.Float32} -> {}] = true
		F.templates.axpy[{concept.Any, concept.Real, &Vec} -> {}] = true
		test[Vec(F)]

		local struct E {}
		E.templates = {}
		E.templates.aypx = template.Template:new("aypx")
		test [Vec(E) == false]

		local struct G {}
		G.templates = {}
		G.templates.axpy = template.Template:new("axpy")
		test [Vec(G) == false]

		local struct H {}
		G.templates = {}
		G.templates.axpy = template.Template:new("axpy")
		G.templates.axpy[{concept.Any, concept.Int8, concept.Float32} -> {}] = true
		test [Vec(G) == false]
	end

    testset "Function declarations" do
        local terra sum1 :: {concept.Real, concept.Real} -> concept.Real
        local terra sum2 :: {float, concept.Integer} -> concept.Float
    end

	testset "Concept from interface" do
		test [Simple:isimplemented(implSimple)]
		test [SimpleC(implSimple)]
	end
end
