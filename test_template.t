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

foo[Integer] = function(T)
	return true
end

foo[Float] = function(T)
	return true
end

foo[{Integer,Integer}] = function(T1, T2)
	return true
end

foo[{Integer,Int32}] = function(T1, T2)
	return true
end

foo[{Int32,Integer}] = function(T1, T2)
	return true
end

foo[{Int32,Integer,Float}] = function(T1, T2, T3)
	return true
end

foo[{Int32,Int32,Float}] = function(T1, T2, T3)
	return true
end

foo[{Int32,Int32,Float64}] = function(T1, T2, T3)
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
end
