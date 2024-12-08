-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local impl = require("concept-impl")
local para = require("concept-parametrized")

local Base = impl.Base
local newconcept = impl.newconcept
local isconcept = impl.isconcept
local Any = impl.Any
local Vararg = impl.Vararg
local methodtag = impl.methodtag
local traittag = impl.traittag
local is_specialized_over = impl.is_specialized_over

local parametrizedconcept = para.parametrizedconcept
local isparametrizedconcept = para.isparametrizedconcept

--concept that carries a value, used to generate concept specialization
--with values (like integers or strings) rather that concepts.
local function Value(n)
    local value = newconcept("Value")
    value.traits.value = n
    return value
end

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

local Stack = newconcept("Stack")
Stack.methods.get = {&Stack, Number} -> Any
Stack.methods.set = {&Stack, Number, Any} -> {}
Stack.methods.size = {&Stack} -> Number

local DStack = newconcept("DStack")
DStack:inherit(Stack)
DStack.methods.push = {&DStack, Any} -> {}
DStack.methods.pop = {&DStack} -> Any
DStack.methods.capacity = {&DStack} -> Integral

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
    Stack = Stack,
    DStack = DStack
}
