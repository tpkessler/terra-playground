-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local io = terralib.includec("stdio.h")
local err = require("assert")
local base = require("base")
local tmath = require("mathfuns")
local concept = require("concept")
local array = require("arraybase")
local vecbase = require("vector")
local veccont = require("vector_contiguous")
local vecblas = require("vector_blas")
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

local SArrayRawType = function(T, Size, options)

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
    if T:isprimitive() then
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
    Array.eltype = T
    Array.ndims = Dimension
    Array.length = Length
    Array.size = Size
    Array.perm = Perm
    Array.ldim = SizeL
    Array.cumsize = Cumsize

    return Array
end

local SArrayStackBase = function(Array)

    local T = Array.eltype
    local N = Array.ndims
    
    terra Array:length() : size_t
        return [Array.length]
    end

    Array.methods.data = macro(function(self, i)
        return `self.data[i]
    end)

    --method size calls static data __size
    local __size = terralib.constant(terralib.new(size_t[N], Array.size))
    Array.methods.size = terralib.overloadedfunction("size", {
        terra(self : &Array, i : size_t)
            return __size[i]
        end,
        terra(self : &Array)
            return __size
        end
    })

    --get lowlevel base functionality for nd arrays
    array.ArrayBase(Array)

    Array.staticmethods.new = terra()
        return Array{}
    end

end

local SArrayVectorBase = function(Array)

    local T = Array.eltype

    vecbase.VectorBase(Array) --add fall-back routines

    Array.staticmethods.all = terra(value : T)
        var A : Array
        for i = 0, A:length() do
            A:set(i, value)
        end
        return A
    end

    if concept.Number(T) then

        Array.staticmethods.zeros = terra()
            return Array.all(T(0))
        end

        Array.staticmethods.ones = terra()
            return Array.all(T(1))
        end

    end

    --specializations using simd operations
    if T:isprimitive() then

        Array.staticmethods.all = terra(value : T)
            var A = Array.new()
            A.simd = value
            return A
        end

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

end

local SArrayIteratorBase = function(Array)

    local T = Array.eltype
    local N = Array.ndims
    local Unitrange = range.Unitrange(int)

    local __uranges = Array.size:map(function(s) return terralib.constant( terralib.new(Unitrange, {0, s}) ) end)

    --return linear indices product range
    terra Array:linear_indices()
        return Unitrange{0, [Array.length]}
    end

    --return linear indices product range
    terra Array:unitrange(i : size_t)
        return Unitrange{0, self:size(i)}
    end

    --return cartesian indices product range
    terra Array:cartesian_indices()
        return range.product([__uranges], {perm = {[Array.perm]}})
    end

    terra Array:rowmajor_cartesian_indixes()
        return range.product([__uranges], {perm = {[array.defaultperm(N)]}})
    end

    --standard iterator is added in VectorBase
    vecbase.IteratorBase(Array) --add fall-back routines

end

local StaticArray = function(T, Size, options)
    
    --generate the raw type
    local Array = SArrayRawType(T, Size, options)
    
    --print typename
    function Array.metamethods.__typename(self)
        local sizes = "{"
        local perm = "{"
        for i = 1, Array.ndims-1 do
            sizes = sizes .. tostring(Array.size[i]) .. ","
            perm = perm .. tostring(Array.perm[i]) .. ","
        end
        sizes = sizes .. tostring(Array.size[Array.ndims]) .. "}"
        perm = perm .. tostring(Array.perm[Array.ndims]) .. "}"
        return "StaticArray(" .. tostring(T) ..", " .. sizes .. ", perm = " .. perm .. ")"
    end
    
    --add base functionality
    base.AbstractBase(Array)

    --implement interfaces
    SArrayStackBase(Array)
    SArrayVectorBase(Array)
    SArrayIteratorBase(Array)

    return Array
end

local StaticVector = terralib.memoize(function(T, N)
    
    --generate the raw type
    local SVector = SArrayRawType(T, {N})
    
    function SVector.metamethods.__typename(self)
        return ("StaticVector(%s, %d)"):format(tostring(T), N)
    end
    
    --add base functionality
    base.AbstractBase(SVector)

    --implement interfaces
    SArrayStackBase(SVector)
    SArrayVectorBase(SVector)
    SArrayIteratorBase(SVector)

    veccont.VectorContiguous:addimplementations{SVector}

    if concept.BLASNumber(T) then
        terra SVector:getblasinfo()
            return self:length(), self:getdataptr(), 1
        end
        vecblas.VectorBLAS:addimplementations{SVector}
    end

    return SVector
end)

local TransposedSMatrix = function(ParentMatrix)

    assert(ParentMatrix.ndims == 2)

    local T = ParentMatrix.eltype
    local Size = terralib.newlist{ParentMatrix.size[2], ParentMatrix.size[1]}
    local Perm = terralib.newlist{ParentMatrix.perm[2], ParentMatrix.perm[1]}

    local SMatrix = SArrayRawType(T, Size, {perm=Perm} )

    function SMatrix.metamethods.__typename(self)
        return ("Transpose{SMatrix(%s, {%d, %d})}"):format(tostring(T), ParentMatrix.size[1], ParentMatrix.size[2])
    end

    --add base functionality
    base.AbstractBase(SMatrix)

    --implement interfaces
    SArrayStackBase(SMatrix)
    SArrayVectorBase(SMatrix)
    SArrayIteratorBase(SMatrix)

    return SMatrix
end

local StaticMatrix = terralib.memoize(function(T, Size, options)
    
    local SMatrix = SArrayRawType(T, Size, options)

    --check that a matrix-type was generated
    assert(SMatrix.ndims == 2, "ArgumentError: second argument should be a table with matrix dimensions.")

    function SMatrix.metamethods.__typename(self)
        return ("StaticMatrix(%s, {%d, %d})"):format(tostring(T), Size{1}, Size{2})
    end

    --add base functionality
    base.AbstractBase(SMatrix)

    --implement interfaces
    SArrayStackBase(SMatrix)
    SArrayVectorBase(SMatrix)
    SArrayIteratorBase(SMatrix)

    local TransposedType = TransposedSMatrix(SMatrix)

    terra SMatrix:transpose()
        return [&TransposedType](self)
    end

    terra TransposedType:transpose()
        return [&SMatrix](self)
    end

    --if concept.BLASNumber(T) then
    --    terra SMatrix:getblasdenseinfo()
    --        return [ SMatrix.size[1] ], [ SMatrix.size[2] ], self:getdataptr(), [ SMatrix.ldim ]
    --    end
    --    local matblas = require("matrix_blas_dense")
    --    matblas.BLASDenseMatrixBase(SMatrix)
    --end

    return SMatrix
end)

local SlicedSMatrix = function(ParentMatrix, ISlice, JSlice)

    assert(ParentMatrix.ndims == 2)
    local T = ParentMatrix.eltype
    local Size = ParentMatrix.size
    local Perm = ParentMatrix.perm



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