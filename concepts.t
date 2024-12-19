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

--traits for primitive types
bool.traits      = {isbool    = true, isprimitive = true}
rawstring.traits = {isstring  = true, isprimitive = true}
--floats
float.traits     = {isfloat   = true, isblasfloat = true, isprimitive = true}
double.traits    = {isfloat   = true, isblasfloat = true, isprimitive = true}
--signed integers
int8.traits      = {isinteger = true, isprimitive = true}
int16.traits     = {isinteger = true, isprimitive = true}
int32.traits     = {isinteger = true, isprimitive = true}
int64.traits     = {isinteger = true, isprimitive = true}
--signed integers
int8.traits      = {isinteger = true, issigned = true, isprimitive = true}
int16.traits     = {isinteger = true, issigned = true, isprimitive = true}
int32.traits     = {isinteger = true, issigned = true, isprimitive = true}
int64.traits     = {isinteger = true, issigned = true, isprimitive = true}
--unsigned integers
uint8.traits     = {isinteger = true, issigned = false, isprimitive = true}
uint16.traits    = {isinteger = true, issigned = false, isprimitive = true}
uint32.traits    = {isinteger = true, issigned = false, isprimitive = true}
uint64.traits    = {isinteger = true, issigned = false, isprimitive = true}

--these traits are used to construct the concept hierarchies of
--real and complex numbers implemented below

local concept Bool
    Self.traits.isbool = true
end

local concept String
    Self.traits.isstring = true
end

local concept Float
    Self.traits.isfloat = true
end

local concept Integer
    Self.traits.isinteger = true
end

local concept SignedInteger
    Self:inherit(Integer)
    Self.traits.issigned = true
end

local concept UnsignedInteger
    Self:inherit(Integer)
    Self.traits.issigned = false
end

local Real = newconcept("Real", function(C, T)
    return Integer(T) or Float(T)
end)

local concept Complex(T) where {T : Real}
    Self.traits.eltype = T
    Self.traits.iscomplex = true
end

local ComplexReal = Complex(Real)

local Number = newconcept("Number", function(C, T)
    return Real(T) or ComplexReal(T)
end)

local concept Primitive
    Self.traits.isprimitive = true
end

local concept BLASFloat
    Self:inherit(Float)
    Self.traits.isblasfloat = true
end

local BLASComplexFloat = Complex(BLASFloat)

local BLASNumber = newconcept("BLASNumber", function(C, T)
    return BLASFloat(T) or BLASComplexFloat(T)
end)

local concept Stack(T) where {T}
    Self.traits.eltype = traittag
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
    Primitive = Primitive,
    Bool = Bool,
    String = String,
    Float = Float,
    Integer = Integer,
    SignedInteger = SignedInteger,
    UnsignedInteger = UnsignedInteger,
    Real = Real,
    Complex = Complex,
    Number = Number,
    BLASFloat = BLASFloat,
    BLASNumber = BLASNumber,
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
