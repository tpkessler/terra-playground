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

local concept NFloat
    Self:inherit(Float)
    Self.traits.precision = traittag
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

local Real = newconcept("Real")
Real:addfriend(Integer)
Real:addfriend(Float)

local concept ComplexOverField(T) where {T : Real}
    Self.traits.eltype = T
    Self.traits.iscomplex = true
end

local Complex = ComplexOverField(Real)

local Number = newconcept("Number")
Number:addfriend(Real)
Number:addfriend(Complex)

local concept Primitive
    Self.traits.isprimitive = true
end

local concept BLASFloat
    Self:inherit(Float)
    Self.traits.isblasfloat = true
end

local BLASComplexFloat = ComplexOverField(BLASFloat)

local BLASNumber = newconcept("BLASNumber")
BLASNumber:addfriend(BLASFloat)
BLASNumber:addfriend(BLASComplexFloat)

local concept Iterator
    Self.methods.getvalue = methodtag
    Self.methods.next = methodtag
    Self.methods.isvalid = methodtag
end

local concept Range
    Self.methods.getiterator = {&Self} -> {Iterator}
end

local concept Stack(T) where {T}
    Self.traits.eltype = traittag
    Self.methods.get  = {&Self, Integer} -> T
    Self.methods.set  = {&Self, Integer, T} -> {}
    Self.methods.size = {&Self} -> Integer
end

local concept DStack(T) where {T}
    Self:inherit(Stack(T))
    Self.methods.push     = {&Self, T} -> {}
    Self.methods.pop      = {&Self} -> T
    Self.methods.capacity = {&Self} -> Integer
end

local concept Vector(T) where {T}
    local S = Stack(T)
    Self:inherit(S)
    Self.methods.fill  = {&Self, T} -> {}
    Self.methods.copy = {&Self, &S} -> {}
    Self.methods.swap = {&Self, &S} -> {}
end

concept Vector(T) where {T : Number}
    local S = Stack(T)
    Self.methods.scal = {&Self, T} -> {}
    Self.methods.axpy = {&Self, T, &S} -> {}
    Self.methods.dot  = {&Self, &S} -> {T}
    Self.methods.sum  = {&Self} -> T
end

concept Vector(T) where {T : Float}
    Self.methods.norm = {&Self} -> {T}
end

local concept ContiguousVector(T) where {T}
    Self:inherit(Vector(T))
    Self.methods.getbuffer = {&Self} -> {Integer, &T}
end

local concept BLASVector(T) where {T : BLASNumber}
    Self:inherit(ContiguousVector(T))
    Self.methods.getblasinfo = {&Self} -> {Integer, BLASNumber, Integer}
end

local concept MatrixStack(T) where {T}
    --Self.methods.size = {&Self, Integer} -> Integer
    Self.methods.get = {&Self, Integer, Integer} -> {T}
    Self.methods.set = {&Self, Integer, Integer, T} -> {}
end

local concept Operator(T) where {T}
    --Self.methods.rows = {&Self} -> Integer
    --Self.methods.cols = {&Self} -> Integer
    Self.methods.apply = {&Self, Bool, T, &Vector(T), T, &Vector(T)} -> {}
end

local concept Matrix(T) where {T}
    local S = MatrixStack(T)
    Self:inherit(S)

    --Self.methods.set = {&Self, Integer, Integer, T} -> {}
    --Self.methods.get = {&Self, Integer, Integer} -> {T}

    --Self.methods.fill = {&Self, T} -> {}
    --Self.methods.clear = {&Self} -> {}
    --Self.methods.copy = {&Self, Bool, &Self} -> {}
    --Self.methods.swap = {&Self, Bool, &Self} -> {}

    --Self.methods.scal = {&Self, T} -> {}
    --Self.methods.axpy = {&Self, T, Bool, &Self} -> {}
    --Self.methods.dot = {&Self, Bool, &Self} -> Number
end

local concept BLASMatrix(T) where {T : BLASNumber}
    Self:inherit(Matrix(T))
    Self.methods.getblasdenseinfo = {&Self} -> {Integer, Integer, &T, Integer}
end

local concept Transpose(M) where {M : Matrix(Any)}
    Self:inherit(M)
    Self.traits.istransposed = true
end

local concept Factorization(T) where {T}
    Self:inherit(Operator(T))
    Self.methods.factorize = {&Self} -> {}
    Self.methods.solve = {&Self, Bool, &Vector(T)} -> {}
end

local concept Packed
    Self.traits.eltype = traittag
    Self.traits.Rows = traittag
    Self.traits.Cols = traittag
end

local concept SparsePacked(T) where {T}
    Self:inherit(Packed)
    Self.traits.eltype = T
    Self.traits.issparse = traittag
end

local concept DensePacked(T) where {T}
    Self:inherit(Packed)
    Self.traits.eltype = T
    Self.traits.isdense = traittag
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
    NFloat = NFloat,
    Integer = Integer,
    SignedInteger = SignedInteger,
    UnsignedInteger = UnsignedInteger,
    Real = Real,
    Complex = Complex,
    ComplexOverField = ComplexOverField,
    Number = Number,
    BLASFloat = BLASFloat,
    BLASNumber = BLASNumber,
    Iterator = Iterator,
    Range = Range,
    Stack = Stack,
    DStack = DStack,
    Vector = Vector,
    ContiguousVector = ContiguousVector,
    BLASVector = BLASVector,
    MatrixStack = MatrixStack,
    Operator = Operator,
    Matrix = Matrix,
    Transpose = Transpose,
    BLASMatrix = BLASMatrix,
    Factorization = Factorization,
    Packed = Packed,
    SparsePacked = SparsePacked,
    DensePacked = DensePacked,
}
