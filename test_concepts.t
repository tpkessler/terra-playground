local concept = require("concept")
local interface = require("interface")

--lua function to create a concept. A concept defines a compile-time 
--predicate that defines an equivalence relation on a set.

--booleans
local Boolean = concept.Concept:new("Boolean", function(T) return T.name == "bool" end)

--primitive number concepts
local Float32 = concept.Concept:new(float)
local Float64 = concept.Concept:new(double)
local Int8    = concept.Concept:new(int8)
local Int16   = concept.Concept:new(int16)
local Int32   = concept.Concept:new(int32)
local Int64   = concept.Concept:new(int64)

-- abstract floating point numbers
local Float = concept.Concept:new("Float")
for _, T in pairs({float, double}) do
	Float:adddefinition(tostring(T), function(Tprime) return Tprime.name == T.name end)
end

--abstract integers
local Integer = concept.Concept:new("Integer")
for _, T in pairs({int8, int16, int32, int64}) do
	Integer:adddefinition(tostring(T), function(Tprime) return Tprime.name == T.name end)
end

local Real = concept.Concept:new("Real", function(T) return Integer(T) or Float(T) end)

local Number = concept.Concept:new("Number", function(T) return Real(T) end)

local Simple = interface.Interface:new{
	foo = Real -> Number
}
local SimpleC = concept.Concept:from_interface("Simple", Simple)

local struct implSimple {}
implSimple.methods.foo = terra(self: &implSimple, x: Real): Number end

--using test library
import "terratest/terratest"

testenv "concepts" do

    testset "Floats" do
        --concrete float
        test [Float64(double)]
        test [Float64(float) == false]
        test [Float64(Float64)]
        --abstract floats
        test [Float(double)]
        test [Float(float)]
        test [Float(Float)]
        test [Float(int32) == false]
        test [Float(double, double) == false]
        test [Float(rawstring) == false]
    end

    testset "Integers" do
        --concrete integers
        test [Int32(int32)]
        test [Int32(int)]
        test [Int32(int16) == false]
        test [Int32(Int32)]
        --abstract floats
        test [Integer(Integer)]
        test [Integer(int)]
        test [Integer(int32)]
        test [Integer(int64)]
        test [Integer(float) == false]
        test [Integer(int, int) == false]
        test [Integer(rawstring) == false]
    end

    testset "Real numbers" do
        test [Real(Integer)]
        test [Real(int32)]
        test [Real(Float)]
        test [Real(float)]
    end

    testset "Numbers" do
        test [Number(Real)]
        test [Number(int32)]
        test [Number(float)]
        test [Number(rawstring) == false]      
    end

    testset "Function declarations" do
        local terra sum1 :: {Real, Real} -> Real
        local terra sum2 :: {float, Integer} -> Float
    end

	testset "Concept from interface" do
		test [Simple:isimplemented(implSimple)]
		test [SimpleC(implSimple)]
	end
end
