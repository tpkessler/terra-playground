local concepts = require("concepts")

--lua function to create a concept. A concept defines a compile-time 
--predicate that defines an equivalence relation on a set.
local concept = concepts.concept

--booleans
local Boolean = concept("Boolean")
Boolean.default = function(T) return T==true or T==false end

--primitive number concepts
local Float32 = concept(float)
local Float64 = concept(double)
local Int8    = concept(int8)
local Int16   = concept(int16)
local Int32   = concept(int32)
local Int64   = concept(int64)

-- abstract floating point numbers
local Float = concept("Float")
Float:adddefinition("float", function(T) return T.name=="float" end)
Float:adddefinition("double", function(T) return T.name=="double" end)

--abstract integers
local Integer = concept("Integer")
Integer:adddefinition("int", function(T) return T.name=="int" end)
Integer:adddefinition("int8", function(T) return T.name=="int8" end)
Integer:adddefinition("int16", function(T) return T.name=="int16" end)
Integer:adddefinition("int32", function(T) return T.name=="int32" end)
Integer:adddefinition("int64", function(T) return T.name=="int64" end)

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
        test [Float("string")==false]
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
        test [Integer("string")==false]
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
        test [Number("string")==false]      
    end

    testset "Function declarations" do
        local terra sum1 :: {Real, Real} -> Real
        local terra sum2 :: {float, Integer} -> Float
    end
end