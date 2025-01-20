-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local io = terralib.includec("stdio.h")
local err = require("assert")
local base = require("base")
local tmath = require("tmath")
local complex = require("complex")
local concepts = require("concepts")
local array = require("arraybase")
local vec = require("vector")
local vecblas = require("vector_blas")
local mat = require("matrix")
local range = require("range")

local size_t = uint64

--global flag to perform boundscheck
__boundscheck__ = true

--there is a bug on macos that leads to undefined behavior for
--simd vectors of size < 64 bytes. temporary fix is to always
--allocate a buffer that's equal or greater than 64 bytes.
local simd_fix_for_macos = function(T, N)
    local nbytes = sizeof(T) * N
    if nbytes < 64 then
        N = 64 / sizeof(T)
    end
    return N
end

local function getcumsize(Size, Perm)
    local Cumsize = terralib.newlist()
    Cumsize[1] = Size[ Perm[1] ]
    for k = 2, #Perm do
        Cumsize[k] = Cumsize[k-1] * Size[Perm[k]]
    end
    return Cumsize
end

local SArrayRawType = function(typename, T, Size, options)

    --check input
    assert(terralib.types.istype(T), "ArgumentError: first argument is not a valid terra type.")
    local Size = terralib.newlist(Size)
    assert(terralib.israwlist(Size) and #Size > 0, "ArgumentError: second argument should be a list denoting the size in each dimension.")
    local Length = 1 --length of array
    for i,v in ipairs(Size) do
        assert(type(v) == "number" and v % 1 == 0 and v > 0, 
            "Expected second to last argument to be positive integers.")
        Length = Length * v
    end

    -- dimension of array
    local Dimension = #Size
    --permutation denoting order of leading dimensions. default is: {D, D-1, ... , 1}
    local Perm = options and options.perm and terralib.newlist(options.perm) or array.defaultperm(Dimension)
    array.checkperm(Perm)
    --get cumulative sizes, which denote the cumulative leading dimensions of the array
    --default is computed from Size and Perm
    local Cumsize = options and options.cumulative_size and terralib.newlist(options.cumulative_size) or getcumsize(Size, Perm)

    --size of leading dimension
    local SizeL = Size[Perm[1]]
    
    --generate static array struct
    local Array
    if concepts.Primitive(T) then
        local N = simd_fix_for_macos(T, Length)
        local SIMD = vector(T, N)
        local M = sizeof(SIMD) / sizeof(T)
        Array = struct{
            union {
                data: T[M]
                simd: SIMD
            }
        }
    else
        Array = struct{
            data: T[Length]
        }
    end

    --global type traits
    local traits = {}
    traits.eltype = T
    traits.ndims = Dimension
    traits.length = Length
    traits.size = Size
    traits.perm = Perm
    traits.ldim = SizeL
    traits.cumsize = Cumsize

    --__typename needs to be called before base.AbstractBase due to some caching 
    --issue with the typename.
    function Array.metamethods.__typename(self)
        return typename(traits)
    end

    --add base functionality - traits, templates table, etc
    base.AbstractBase(Array)
    
    --add traits to Array.traits table
    for key,val in pairs(traits) do
        Array.traits[key] = val
    end

    return Array
end

local SArrayStackBase = function(Array)

    local T = Array.traits.eltype
    local N = Array.traits.ndims
    
    terra Array:length() : size_t
        return [Array.traits.length]
    end

    terra Array:getdataptr() : &T
        return &self.data[0]
    end

    if not Array.methods.getdata then
        Array.methods.getdata = macro(function(self, i)
            return `self.data[i]
        end)
    end

    if not Array.methods.setdata then
        Array.methods.setdata = macro(function(self, i, v)
            return quote self.data[i] = v end
        end)
    end

    --method size calls static data __size
    local __size = terralib.constant(terralib.new(size_t[N], Array.traits.size))
    if not Array.methods.size then
        Array.methods.size = terralib.overloadedfunction("size", {
            terra(self : &Array, i : size_t)
                return __size[i]
            end,
            terra(self : &Array)
                return __size
            end
        })
    end

    --get lowlevel base functionality for nd arrays
    array.ArrayBase(Array)

    Array.staticmethods.new = terra()
        return Array{}
    end

end

local SArrayVectorBase = function(Array)

    local T = Array.traits.eltype

    --add basic falback routines
    vec.VectorBase(Array)

    --add level-1 BLAS fall-back routines
    if concepts.BLASNumber(T) then
        terra Array:getblasinfo()
            return self:length(), self:getdataptr(), 1
        end
        vecblas.BLASVectorBase(Array)
    end

    if concepts.Real(T) and concepts.Primitive(T) then
        Array.staticmethods.all = terra(value : T)
            var A = Array.new()
            A.simd = value
            return A
        end
    else
        Array.staticmethods.all = terra(value : T)
            var A : Array
            for i = 0, A:length() do
                A:set(i, value)
            end
            return A
        end
    end

    --static methods that operate on numbers
    if concepts.Number(T) then

        Array.staticmethods.zeros = terra()
            return Array.all(T(0))
        end

        Array.staticmethods.ones = terra()
            return Array.all(T(1))
        end

    end

    --specialized methods using simd operations
    if concepts.Primitive(T) then

        terra Array:fill(v : T)
            self.simd = v
        end

        terra Array:copy(other : &Array)
            self.simd = other.simd
        end

        terra Array:scal(a : T)
            self.simd = a * self.simd
        end

        terra Array:axpy(a : T, x : &Array)
            self.simd = self.simd + a * x.simd
        end

    end

    --check if vector concept is satisfied
    local CVector = concepts.Vector(T)
    assert(CVector(Array), "ConceptError: " .. tostring(Array) .. " does not satisfy concept " .. tostring(CVector))

end


local SArrayMatrixBase = function(SMatrix)
    
    assert(SMatrix.traits.ndims == 2) --these methods are only for matrices
    local T = SMatrix.traits.eltype

    terra SMatrix:rows()
        return self:size(0)
    end
    SMatrix.methods.rows:setinlined(true)

    terra SMatrix:cols()
        return self:size(1)
    end
    SMatrix.methods.cols:setinlined(true)

    if concepts.BLASNumber(T) then
        terra SMatrix:getblasdenseinfo()
            return [ SMatrix.traits.size[1] ], [ SMatrix.traits.size[2] ], self:getdataptr(), [ SMatrix.traits.ldim ]
        end
    end

end


local SArrayIteratorBase = function(Array)

    local T = Array.traits.eltype
    local N = Array.traits.ndims
    local Unitrange = range.Unitrange(int)

    local __uranges = Array.traits.size:map(function(s) return terralib.constant( terralib.new(Unitrange, {0, s}) ) end)

    --return linear indices product range
    terra Array:linear_indices()
        return Unitrange{0, [Array.traits.length]}
    end

    --return linear indices product range
    terra Array:unitrange(i : size_t)
        return Unitrange{0, self:size(i)}
    end

    --return cartesian indices product range
    terra Array:cartesian_indices()
        return range.product([__uranges], {perm = {[Array.traits.perm]}})
    end

    terra Array:rowmajor_cartesian_indixes()
        return range.product([__uranges], {perm = {[array.defaultperm(N)]}})
    end

    --standard iterator
    vec.IteratorBase(Array)
end

local StaticArray = function(T, Size, options)
    
    --print typename
    local function typename(traits)
        local sizes = "{"
        local perm = "{"
        for i = 1, traits.ndims-1 do
            sizes = sizes .. tostring(size[i]) .. ","
            perm = perm .. tostring(traits.perm[i]) .. ","
        end
        sizes = sizes .. tostring(traits.size[traits.ndims]) .. "}"
        perm = perm .. tostring(traits.perm[traits.ndims]) .. "}"
        return "StaticArray(" .. tostring(T) ..", " .. sizes .. ", perm = " .. perm .. ")"
    end

    --generate the raw type
    local Array = SArrayRawType(typename, T, Size, options)

    --implement interfaces
    SArrayStackBase(Array)
    SArrayVectorBase(Array)
    SArrayIteratorBase(Array)

    return Array
end

--StaticVector is reimplemented separately from 'Array' because otherwise
--SVector.metamethods.__typename is memoized incorrectly
local StaticVector = terralib.memoize(function(T, N)
    
    local function typename(traits)
        return ("StaticVector(%s, %d)"):format(tostring(T), N)
    end

    --generate the raw type
    local SVector = SArrayRawType(typename, T, {N})

    --implement interfaces
    SArrayStackBase(SVector)
    SArrayVectorBase(SVector)
    SArrayIteratorBase(SVector)

    return SVector
end)

local TransposedSMatrix = function(ParentMatrix)

    assert(ParentMatrix.traits.ndims == 2)

    local T = ParentMatrix.traits.eltype
    local Size = terralib.newlist{ParentMatrix.traits.size[2], ParentMatrix.traits.size[1]}
    local Perm = terralib.newlist{ParentMatrix.traits.perm[2], ParentMatrix.traits.perm[1]}

    local typename
    if concepts.Complex(T) then
        typename = function(traits)
            return ("ConjugateTranspose{SMatrix(%s, {%d, %d})}"):format(tostring(T), ParentMatrix.traits.size[1], ParentMatrix.traits.size[2])
        end
    else
        typename = function(traits)
            return ("Transpose{SMatrix(%s, {%d, %d})}"):format(tostring(T), ParentMatrix.traits.size[1], ParentMatrix.traits.size[2])
        end
    end

    local SMatrix = SArrayRawType(typename, T, Size, {perm=Perm} )

    --trait to signal that this is a transposed view
    SMatrix.traits.istransposed = true

    --overload the set / get behavior to get conjugate transpose
    --for complex data types
    if concepts.Complex(T) then
        SMatrix.methods.getdata = macro(function(self, i)
            return `tmath.conj(self.data[i])
        end)
        SMatrix.methods.setdata = macro(function(self, i, v)
            return quote self.data[i] = tmath.conj(v) end
        end)
    end

    --implement interfaces
    SArrayStackBase(SMatrix)
    SArrayVectorBase(SMatrix)
    SArrayIteratorBase(SMatrix)
    SArrayMatrixBase(SMatrix)

    return SMatrix
end

local StaticMatrix = terralib.memoize(function(T, Size, options)

    local function typename(traits)
        return ("StaticMatrix(%s, {%d, %d})"):format(tostring(T), Size{1}, Size{2})
    end

    local SMatrix = SArrayRawType(typename, T, Size, options)

    --check that a matrix-type was generated
    assert(SMatrix.traits.ndims == 2, "ArgumentError: second argument should be a table with matrix dimensions.")

    --implement interfaces
    SArrayStackBase(SMatrix)
    SArrayVectorBase(SMatrix)
    SArrayIteratorBase(SMatrix)
    SArrayMatrixBase(SMatrix)

    local TransposedType = TransposedSMatrix(SMatrix)

    terra SMatrix:transpose()
        return [&TransposedType](self)
    end

    terra TransposedType:transpose()
        return [&SMatrix](self)
    end

    return SMatrix
end)

local SlicedSMatrix = function(ParentMatrix, ISlice, JSlice)

end

return {
    StaticArray = StaticArray,
    SArrayRawType = SArrayRawType,
    SArrayStackBase = SArrayStackBase,
    SArrayVectorBase = SArrayVectorBase,
    SArrayIteratorBase = SArrayIteratorBase,
    StaticVector = StaticVector,
    StaticMatrix = StaticMatrix
}