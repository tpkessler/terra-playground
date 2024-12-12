-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"

local impl = require("concept-impl")
local para = require("concept-parametrized")

local Base = impl.Base
local newconcept = impl.newconcept
local isconcept = impl.isconcept
local Any = impl.Any
local Value = impl.Value
local ParametrizedValue = impl.ParametrizedValue
local Vararg = impl.Vararg
local methodtag = impl.methodtag
local traittag = impl.traittag
local is_specialized_over = impl.is_specialized_over

local parametrizedconcept = para.parametrizedconcept
local isparametrizedconcept = para.isparametrizedconcept

local Bool = newconcept("Bool")
Bool:addfriend(bool)

local RawString = newconcept("RawString")
RawString:addfriend(rawstring)

local Float = newconcept("Float")
local F = {}
for suffix, T in pairs({["32"] = float, ["64"] = double}) do
	local name = "Float" .. suffix
	F[name] = newconcept(name)
    F[name]:addfriend(T)
    Float:addfriend(T)
end

local I = {}
for _, prefix in pairs({"", "u"}) do
	local cname = prefix:upper() .. "Integer"
	I[cname] = newconcept(cname)
	for _, suffix in pairs({8, 16, 32, 64}) do
		local name = prefix:upper() .. "Int" .. tostring(suffix)
		local terra_name = prefix .. "int" .. tostring(suffix)
		-- Terra primitive types are global lua variables
		local T = _G[terra_name] 
		I[name] = newconcept(name)
		I[name]:addfriend(T)
		I[cname]:addfriend(T)
	end
end

local function append_friends(C, D)
    for k, v in pairs(D.friends) do
        C.friends[k] = v
    end
end

local Integral = newconcept("Integral")
for _, C in pairs({I.Integer, I.UInteger}) do
    append_friends(Integral, C)
end

local Real = newconcept("Real")
for _, C in pairs({Float, I.Integer}) do
    append_friends(Real, C)
end

local Number = newconcept("Number")
for _, C in pairs({Float, I.Integer, I.UInteger}) do
    append_friends(Number, C)
end

local BLASNumber = newconcept("BLASNumber")
BLASNumber:addfriend(float)
BLASNumber:addfriend(double)

local Primitive = newconcept("Primitive")
for _, C in pairs({I.Integer, I.UInteger, Bool, Float}) do
	append_friends(Primitive, C)
end

local concept Iterator
    Self.methods.getvalue = methodtag
    Self.methods.next = methodtag
    Self.methods.isvalid = methodtag
end

local concept Range
    Self.methods.getiterator = {&Self} -> {Iterator}
end

local concept Stack(T) where {T}
    Self.methods.get  = {&Self, Integral} -> T
    Self.methods.set  = {&Self, Integral, T} -> {}
    Self.methods.size = {&Self} -> Integral
end

local concept DStack(T) where {T}
    Self:inherit(Stack(T))
    Self.methods.push     = {&Self, T} -> {}
    Self.methods.pop      = {&Self} -> T
    Self.methods.capacity = {&Self} -> Integral
end

local concept Vector(T) where {T}
    Self:inherit(Stack(T))
    Self.methods.fill  = {&Self, T} -> {}
    Self.methods.clear = {&Self} -> {}
    Self.methods.sum   = {&Self} -> T
end

concept Vector(T) where {T : Number}
    local S = Stack(T)
    Self.methods.copy = {&Self, &S} -> {}
    Self.methods.swap = {&Self, &S} -> {}
    Self.methods.scal = {&Self, T} -> {}
    Self.methods.axpy = {&Self, T, &S} -> {}
    Self.methods.dot  = {&Self, &S} -> {T}
end

concept Vector(T) where {T : Float}
    Self.methods.norm = {&Self} -> {T}
end

local concept ContiguousVector(T) where {T}
    Self:inherit(Vector(T))
    Self.methods.getbuffer = {&Self} -> {Integral, &T}
end

local concept BLASVector(T) where {T : BLASNumber}
    Self:inherit(ContiguousVector(T))
    Self.methods.getblasinfo = {&Self} -> {Integral, BLASNumber, Integral}
end

local concept Operator(T) where {T}
    Self.methods.rows = {&Self} -> Integral
    Self.methods.cols = {&Self} -> Integral
    Self.methods.apply = {&Self, Bool, T, &Vector(T), T, &Vector(T)} -> {}
end

local concept Matrix(T) where {T}
    Self:inherit(Operator(T))
    Self.methods.set = {&Self, Integral, Integral, T} -> {}
    Self.methods.get = {&Self, Integral, Integral} -> {T}

    Self.methods.fill = {&Self, T} -> {}
    Self.methods.clear = {&Self} -> {}
    Self.methods.copy = {&Self, Bool, &Self} -> {}
    Self.methods.swap = {&Self, Bool, &Self} -> {}

    Self.methods.scal = {&Self, T} -> {}
    Self.methods.axpy = {&Self, T, Bool, &Self} -> {}
    Self.methods.dot = {&Self, Bool, &Self} -> Number
    Self.methods.mul = {&Self, T, T, Bool, &Self, Bool, &Self} -> {}
end

local concept BLASDenseMatrix(T) where {T : BLASNumber}
    Self:inherit(Matrix(T))
    Self.methods.getblasdenseinfo = {&Self} -> {Integral, Integral, &BLASNumber, Integral}
end

local concept Factorization(T) where {T}
    Self:inherit(Operator(T))
    Self.methods.factorize = {&Self} -> {}
    Self.methods.solve = {&Self, Bool, &Vector(T)} -> {}
end

return {
    Base = Base,
    isconcept = isconcept,
    newconcept = newconcept,
    methodtag = methodtag,
    traittag = traittag,
    is_specialized_over = is_specialized_over,
    parametrizedconcept = parametrizedconcept,
    isparametrizedconcept = isparametrizedconcept,
    Any = Any,
    Vararg = Vararg,
    Value = Value,
    ParametrizedValue = ParametrizedValue,
    Bool = Bool,
    RawString = RawString,
    Float = Float,
    Float32 = F.Float32,
    Float64 = F.Float64,
    Integer = I.Integer,
    UInteger = I.UInteger,
    Int8 = I.Int8,
    Int16 = I.Int16,
    Int32 = I.Int32,
    Int64 = I.Int64,
    UInt8 = I.UInt8,
    UInt16 = I.UInt16,
    UInt32 = I.UInt32,
    UInt64 = I.UInt64,
    Integral = Integral,
    Real = Real,
    BLASNumber = BLASNumber,
    Number = Number,
    Primitive = Primitive,
    Iterator = Iterator,
    Range = Range,
    Stack = Stack,
    DStack = DStack,
    Vector = Vector,
    ContiguousVector = ContiguousVector,
    BLASVector = BLASVector,
    Operator = Operator,
    Matrix = Matrix,
    BLASDenseMatrix = BLASDenseMatrix,
    Factorization = Factorization
}
