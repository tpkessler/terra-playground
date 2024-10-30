-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concept = require("concept")
local template = require("template")

import "terratest/terratest"

testenv "concepts" do

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
        --abstract floats
        test [concept.is_specialized_over(concept.Integer, concept.Integer)]
        test [concept.Integer(int)]
        test [concept.Integer(int32)]
        test [concept.Integer(int64)]
        test [concept.Integer(float) == false]
        test [concept.Integer(rawstring) == false]
    end

    testset "Real numbers" do
        test [concept.is_specialized_over(concept.Integer, concept.Real)]
        test [concept.Real(int32)]
        test [concept.Real(int64)]
        test [concept.is_specialized_over(concept.Float, concept.Real)]
        test [concept.Real(float)]
        test [concept.Real(double)]
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

	testset "Pointers" do
	end

	testset "Empty abstract interface" do
		local EmptyInterface = concept.AbstractInterface:new("Empty")
		test [concept.isconcept(EmptyInterface)]
	end

	testset "Abstract interface" do
		local SimpleInterface = concept.AbstractInterface:new("SimpleAbs")
		test [concept.isconcept(SimpleInterface)]
		
		SimpleInterface:addmethod{cast = concept.Integer -> concept.Real}
		local struct B {}
		terra B:cast(x: int8) : float end
		test [SimpleInterface(B)]
	end

	testset "Self-referencing interface on methods" do
		local Vec = concept.AbstractInterface:new("Vec")
		test [concept.isconcept(Vec)]
		Vec:addmethod{axpy = {concept.Real, &Vec} -> {}}

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
		local Vec = concept.AbstractInterface:new("Vec2")
		test [concept.isconcept(Vec)]
		Vec:addmethod{axpy = {concept.Real, &Vec} -> {}}

		local struct F {}
		F.templates = {}

		F.templates.axpy = template.Template:new("axpy")
		F.templates.axpy[template.paramlist.new({concept.Any, concept.Int8, concept.Float32},{1,2,3})] = true
		F.templates.axpy[template.paramlist.new({concept.Any, concept.Real, &Vec},{1,2,3})] = true
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
		G.templates.axpy[template.paramlist.new({concept.Any, concept.Int8, concept.Float32},{1,2,3})] = true
		test [Vec(G) == false]
	end
end
