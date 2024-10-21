-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local template = require("template")
local concept = require("concept")

import "terratest/terratest"

-- lua function to create a concept.
-- A concept defines defines a compile-time predicate that defines an equivalence
-- relation on a set.
local Concept = concept.Concept

--primitive number concepts
local Float32 = concept.Float32
local Float64 = concept.Float64
local Int8    = concept.Int8
local Int16   = concept.Int16
local Int32   = concept.Int32
local Int64   = concept.Int64

-- abstract floating point numbers
local Float = concept.Float

--abstract integers
local Integer = concept.Integer

--test foo template implementation
local foo = template.Template:new()

foo[Integer -> {}] = function(T)
	return true
end

foo[Float -> Float] = function(T)
	return true
end

foo[{Integer, Integer} -> {}] = function(T1, T2)
	return true
end

foo[{Integer, Int32} -> {}] = function(T1, T2)
	return true
end

foo[{Int32, Integer} -> {}] = function(T1, T2)
	return true
end

foo[{Int32, Integer, Float} -> {}] = function(T1, T2, T3)
	return true
end

foo[{Int32, Int32, Float} -> {}] = function(T1, T2, T3)
	return true
end

foo[{Int32, Int32, Float64} -> {}] = function(T1, T2, T3)
	return true
end


testenv "templates" do
	for _, T in pairs({double, float, int32}) do
		testset(T) "Single arguments" do
			local ok, ret = pcall(function(Tprime) return foo(Tprime) end, T)
			test ok == true
			test ret == true
		end
	end

	for _, Targs in pairs({{int64, int64}, {int32, int32, double}}) do
		local args = tostring(terralib.newlist(Targs))
		testset(args) "Multiple arguments" do
			local ok, ret = pcall(function(...) return foo(...) end, unpack(Targs))
			test ok == true
			test ret == true
		end
	end

	testset "Ambiguous call" do
		local ok, ret = pcall(function(T1, T2) return foo(T1, T2) end, int32, int32)
		test ok == false
		local i, j = ret:find("Method call is ambiguous.")
		test i > 1
	end

	testset "No function pointer as argument" do
		local ok, ret = pcall(function()
			foo[Float] = function(T)
				return true
			end
		end)
		test ok == false
		local i, j = ret:find("Need to pass function pointer")
		test i > 1
	end
end

testenv "Function templates" do
	testset "Single definition" do
		local f = template.functiontemplate(
			"add",
			{
				[concept.Integer -> concept.Integer] = function(I)
					return terra(x: I) return x + 1 end
				end
			}
		)

		for _, I in pairs({int8, int16, int32, int64}) do
			local ok, ret = pcall(
				function(f) return f:dispatch(I) end,
				f
			)
			local is_function = terralib.isfunction(ret)

			test ok == true
			test is_function == true
		end

		for _, I in pairs({float, double, uint32, bool}) do
			local ok, ret = pcall(
				function(f) return f:dispatch(I) end,
				f
			)
			test ok == false
		end

		local g = f:dispatch(int32)
		terracode
			var x = 11
			var ref = 12
			var resf = f(x)
			var resg = g(x)
		end

		test resf == ref
		test resg == ref
	end

	testset "Multiple definition" do
		local f = template.functiontemplate(
			"add",
			{
				[concept.Float -> concept.Float] = function(F)
					return terra(x: F) return 2.0 * x end
				end
			})
		f:adddefinition{
			[{concept.Float, concept.Float} -> concept.Float] = (
				function(F1, F2)
					return terra(x: F1, y: F2) return x * y end
				end
			)
		}

		local g = f:dispatch(double)
		local h = f:dispatch(float, double)
		terracode
			var x = 3.0
			var y = 2.5f

			var ref1 = 6.0
			var resf1 = f(x)
			var resg = g(x)

			var ref2 = 7.5
			var resf2 = f(y, x)
			var resh = h(y, x)
		end

		test ref1 == resf1
		test ref1 == resg

		test ref2 == resf2
		test ref2 == resh
	end
end
