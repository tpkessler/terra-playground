local concepts = require("concept")

--lua function to create a concept. A concept defines a compile-time 
--predicate that defines an equivalence relation on a set.
local concept = concepts.concept

--booleans
local Boolean = concept("Boolean")
Boolean.default = function(T) return T == bool end

--primitive number concepts
local Float32 = concept(float)
local Float64 = concept(double)
local Int8    = concept(int8)
local Int16   = concept(int16)
local Int32   = concept(int32)
local Int64   = concept(int64)

-- abstract floating point numbers
local Float = concept("Float")
for _, T in pairs({float, double}) do
	Float:adddefinition(tostring(T), function(Tprime) return Tprime == T end)
end

--abstract integers
local Integer = concept("Integer")
for _, T in pairs({int8, int16, int32, int64}) do
	Integer:adddefinition(tostring(T), function(Tprime) return Tprime == T end)
end

local Real = concept("Real")
Real.default = function(T) return Integer(T) or Float(T) end

local Number = concept("Number")
Number.default = function(T) return Real(T) end

--using test library
import "terratest/terratest"

testenv "concepts" do

    testset "Floats" do
        --concrete float
        test [Float64(double)]
        test [Float64(float)==false]
        test [Float64(Float64)]
        --abstract floats
        test [Float(double)]
        test [Float(float)]
        test [Float(Float)]
        test [Float(int32)==false]
        test [Float(double, double)==false]
        test [Float(rawstring)==false]
    end

    testset "Integers" do
        --concrete integers
        test [Int32(int32)]
        test [Int32(int)]
        test [Int32(int16)==false]
        test [Int32(Int32)]
        --abstract floats
        test [Integer(Integer)]
        test [Integer(int)]
        test [Integer(int32)]
        test [Integer(int64)]
        test [Integer(float)==false]
        test [Integer(int, int)==false]
        test [Integer(rawstring)==false]
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
        test [Number(rawstring)==false]      
    end

    testset "Function declarations" do
        local terra sum1 :: {Real, Real} -> Real
        local terra sum2 :: {float, Integer} -> Float
    end
end
