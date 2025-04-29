-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local io = terralib.includec("stdio.h")
local err = require("assert")
local alloc = require("alloc")
local base = require("base")
local tmath = require("tmath")
local concepts = require("concepts")
local array = require("arraybase")
local vec = require("vector")
local vecblas = require("vector_blas")
local stack = require("stack")
local mat = require("matrix")
local range = require("range")
local tup = require("tuple")

local luafun = require("fun")

local Allocator = alloc.Allocator
local size_t = uint64

--global flag to perform boundscheck
__boundscheck__ = true


local DArrayRawType = function(typename, T, Dimension, options)

    --check input
    assert(terralib.types.istype(T), "ArgumentError: first argument is not a valid terra type.")

    --permutation denoting order of leading dimensions. default is: {D, D-1, ... , 1}
    local Perm = options and options.perm and terralib.newlist(options.perm) or array.defaultperm(Dimension)
    array.checkperm(Perm)
    
    --generate static array struct
    local S = alloc.SmartBlock(T)

    local struct Array{
        data : S
        size : size_t[Dimension]
        cumsize : size_t[Dimension] --cumulative product dimensions - is ordered according to 'perm'
    }

    --global type traits
    local traits = {}
    traits.eltype = T
    traits.ndims = Dimension
    traits.perm = Perm

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

local DArrayStackBase = function(Array)

    local T = Array.traits.eltype
    local N = Array.traits.ndims

    terra Array:length() : size_t
        return self.cumsize[ [N-1] ]
    end
    
    terra Array:getdataptr() : &T
        return &self.data(0)
    end

    if not Array.methods.getdata then
        Array.methods.getdata = macro(function(self, i)
            return `self.data(i)
        end)
    end

    if not Array.methods.setdata then
        Array.methods.setdata = macro(function(self, i, v)
            return quote self.data(i) = v end
        end)
    end

    --element size as a terra method
    if not Array.methods.size then
        Array.methods.size = terralib.overloadedfunction("size", {
            terra(self : &Array, i : size_t)
                return self.size[i]
            end,
            terra(self : &Array)
                return self.size
            end
        })
    end

    --get lowlevel base functionality for nd arrays
    local arraybase = array.ArrayBase(Array)

    local terra getcumsize(size : size_t[N])
        var cumsize : size_t[N]
        escape
            local p = Array.traits.perm[1]
            emit quote cumsize[0] = size[ [p-1] ] end
            for k = 2, N do
                local p = Array.traits.perm[k]
                emit quote cumsize[ [k-1] ] = cumsize[ [k-2] ] * size[ [p - 1] ] end
            end
        end
        return cumsize
    end

    --create a new dynamic array
    --ToDo: fix terralib typechecker to perform raii initializers correctly
    local new = terra(alloc: Allocator, size : tup.ntuple(size_t, N))
        var __size = [ &size_t[N] ](&size)  --we need the size as an array
        var cumsize = getcumsize(@__size)   --compute cumulative sizes
        var length = cumsize[N-1]           --length is last entry in 'cumsum'
        return Array{alloc:new(sizeof(T), length), @__size, cumsize}
    end

    --For N==1 we allow passing the size as an integer or as a tuple holding
    --a single integer
    if N==1 then
        Array.staticmethods.new = terralib.overloadedfunction("new", {
            new,
            terra(alloc: Allocator, size : size_t)
                return new(alloc, {size})
            end
        })
    else
        Array.staticmethods.new = new
    end

    local terra resize(self: &Array, newsize: tup.ntuple(size_t, N))
        var size = @[ &size_t[N] ](&newsize)
        var cumsize = getcumsize(size)
        var length = cumsize[N - 1]
        var A = self.data.alloc
        A:__allocators_best_friend(&self.data, sizeof(T), length)
        self.size = size
        self.cumsize = cumsize
    end

    if N == 1 then
        Array.methods.resize = terralib.overloadedfunction("resize",
            {
                resize,
                terra(self: &Array, newsize: size_t)
                    return resize(self, {newsize})
                end
            }
        )
    else
        Array.methods.resize = resize
    end

    local S = alloc.SmartBlock(T)

    Array.methods.like = terra(self: &Array)
        var A = self.data.alloc
        var newself: Array
        var length = self.cumsize[N - 1]
        A:__allocators_best_friend(&newself.data, sizeof(T), length)
        newself.size = self.size
        newself.cumsize = self.cumsize
        return newself
    end

    Array.staticmethods.frombuffer = (
        terra(size : tup.ntuple(size_t, N), data : &T)
            var __size = [ &size_t[N] ](&size)  --we need the size as an array
            var cumsize = getcumsize(@__size)   --compute cumulative sizes
            var length = cumsize[N-1]           --length is last entry in 'cumsum'
            return Array{S.frombuffer(length, data), @__size, cumsize}
        end
    )

    --for N==1 we allow casting from a dynamic stack
    if N==1 then
        local dstack = stack.DynamicStack(T)

        Array.metamethods.__cast = function(from, to, exp)
            if from == dstack and to == Array then
                --only allow rvalues to be cast from a dstack to a dvector
                --a dynamic stack can reallocate, which makes it unsafe to cast
                --an lvalue since the lvalue may be modified (reallocate) later
                return quote
                    var tmp = __move__(exp)
                    var v : Array
                    v.data = __move__(tmp.data) --we move the resources over
                    v.size[0] = tmp.size --as size we provide the whole resource
                    v.cumsize[0] = v.size[0]
                in
                    __move__(v)
                end
            else
                error("ArgumentError: not able to cast " .. tostring(from) .. " to " .. tostring(to) .. ".")
            end
        end
    end

end

local DArrayVectorBase = function(Array)

    local T = Array.traits.eltype
    local N = Array.traits.ndims
    local Sizes = tup.ntuple(size_t, N)

    vec.VectorBase(Array) --add fall-back routines

    --add level-1 BLAS fall-back routines
    if concepts.BLASNumber(T) then
        terra Array:getblasinfo()
            return self:length(), self:getdataptr(), 1
        end
        vecblas.BLASVectorBase(Array)
    end

    local all = function(S)
        return terra(alloc : Allocator, size : S, value : T)
            var A = Array.new(alloc, size)
            for i = 0, A:length() do
                A:set(i, value)
            end
            return A
        end
    end

    local zeros = function(S)
        return terra(alloc : Allocator, size : S)
            return Array.all(alloc, size, T(0))
        end
    end

    local ones = function(S)
        return terra(alloc : Allocator, size : S)
            return Array.all(alloc, size, T(1))
        end
    end

    if N == 1 then
        Array.staticmethods.all = terralib.overloadedfunction("all", {all(size_t), all(Sizes)})

        if concepts.Number(T) then
            Array.staticmethods.zeros = terralib.overloadedfunction("zeros", {zeros(size_t), zeros(Sizes)})
            Array.staticmethods.ones = terralib.overloadedfunction("ones", {ones(size_t), ones(Sizes)})
        end
    else
        Array.staticmethods.all = all(Sizes)
        
        if concepts.Number(T) then
            Array.staticmethods.zeros = zeros(Sizes)
            Array.staticmethods.ones = ones(Sizes)
        end
    end

    --check if vector concept is satisfied
    local CVector = concepts.Vector(T)
    assert(CVector(Array), "ConceptError: " .. tostring(Array) .. " does not satisfy concept " .. tostring(CVector))
end


local DArrayMatrixBase = function(DMatrix)
    
    assert(DMatrix.traits.ndims == 2) --these methods are only for matrices
    local T = DMatrix.traits.eltype

    terra DMatrix:rows()
        return self:size(0)
    end
    DMatrix.methods.rows:setinlined(true)

    terra DMatrix:cols()
        return self:size(1)
    end
    DMatrix.methods.cols:setinlined(true)

    if concepts.BLASNumber(T) then
        terra DMatrix:getblasdenseinfo()
            return self:size(0), self:size(1), self:getdataptr(), self.cumsize[0]
        end
    end

end

local DArrayIteratorBase = function(Array)

    local T = Array.traits.eltype
    local N = Array.traits.ndims
    local Unitrange = range.Unitrange(int)

    --get lowlevel base functionality for nd arrays
    local arraybase = array.ArrayBase(Array)

    --return linear indices product range
    terra Array:linear_indices()
        return Unitrange{0, self:length()}
    end

    --return linear indices product range
    terra Array:unitrange(i : size_t)
        return Unitrange{0, self:size(i)}
    end

    --get unitranges in all array dimensions
    local unitranges = arraybase.getunitranges(N)

    --return cartesian indices product range
    terra Array:cartesian_indices()
        var K = unitranges(self)
        return range.product(unpacktuple(K), {perm = {[Array.traits.perm]}})
    end

    terra Array:rowmajor_cartesian_indixes()
        var K = unitranges(self)
        return range.product(unpacktuple(K), {perm = {[array.defaultperm(N)]}})
    end

    --standard iterator is added in VectorBase
    vec.IteratorBase(Array) --add fall-back routines
 
end

local DynamicArray = function(T, Dimension, options)
    
    --print typename
    local function typename(traits)
        local sizes = "{"
        local perm = "{"
        for i = 1, traits.ndims-1 do
            perm = perm .. tostring(traits.perm[i]) .. ","
        end
        perm = perm .. tostring(traits.perm[traits.ndims]) .. "}"
        return "DynamicArray(" .. tostring(T) ..", " .. tostring(traits.ndims) .. ", perm = " .. perm .. ")"
    end

    --generate the raw type
    local Array = DArrayRawType(typename, T, Dimension, options)
    
    --implement interfaces
    DArrayStackBase(Array)
    DArrayVectorBase(Array)
    DArrayIteratorBase(Array)

    return Array
end

--DynamicVector is reimplemented separately from 'Array' because otherwise
--DynamicVector.metamethods.__typename is memoized incorrectly
local DynamicVector = terralib.memoize(function(T)
    
    local function typename(traits)
        return ("DynamicVector(%s)"):format(tostring(T))
    end

    --generate the raw type
    local DVector = DArrayRawType(typename, T, 1)

    --implement interfaces
    DArrayStackBase(DVector)
    DArrayVectorBase(DVector)
    DArrayIteratorBase(DVector)

    return DVector
end)

local TransposedDMatrix = function(ParentMatrix)

    assert(ParentMatrix.traits.ndims == 2)

    local T = ParentMatrix.traits.eltype
    local Perm = terralib.newlist{ParentMatrix.traits.perm[2], ParentMatrix.traits.perm[1]}

    local typename
    if concepts.Complex(T) then
        typename = function(traits)
            return ("ConjugateTranspose{DMatrix(%s)}"):format(tostring(T))
        end
    else
        typename = function(traits)
            return ("Transpose{DMatrix(%s)}"):format(tostring(T))
        end
    end

    local DMatrix = DArrayRawType(typename, T, 2, {perm=Perm})

    --trait to signal that this is a transposed view
    DMatrix.traits.istransposed = true

    --overload the set / get behavior to get conjugate transpose
    --for complex data types
    if concepts.Complex(T) then
        DMatrix.methods.getdata = macro(function(self, i)
            return `tmath.conj(self.data(i))
        end)
        DMatrix.methods.setdata = macro(function(self, i, v)
            return quote self.data(i) = tmath.conj(v) end
        end)
    end

    DMatrix.methods.size = terralib.overloadedfunction("size", {
        terra(self : &DMatrix, i : size_t)
            return self.size[1-i]
        end,
        terra(self : &DMatrix)
            return self.size[1], self.size[0]
        end
    })

    --implement interfaces
    DArrayStackBase(DMatrix)
    DArrayVectorBase(DMatrix)
    DArrayIteratorBase(DMatrix)
    DArrayMatrixBase(DMatrix)

    return DMatrix
end


local DynamicMatrix = terralib.memoize(function(T, options)

    local function typename(traits)
        return ("DynamicMatrix(%s)"):format(tostring(T))
    end

    local DMatrix = DArrayRawType(typename, T, 2, options)

    --check that a matrix-type was generated
    assert(DMatrix.traits.ndims == 2, "ArgumentError: second argument should be a table with matrix dimensions.")

    --implement interfaces
    DArrayStackBase(DMatrix)
    DArrayVectorBase(DMatrix)
    DArrayIteratorBase(DMatrix)
    DArrayMatrixBase(DMatrix)

    local TransposedType = TransposedDMatrix(DMatrix)

    terra DMatrix:transpose()
        return [&TransposedType](self)
    end

    terra TransposedType:transpose()
        return [&DMatrix](self)
    end

    local Matrix = concepts.Matrix(T)
    assert(Matrix(DMatrix), "Type " .. tostring(DMatrix)
                              .. " does not implement the matrix interface")

    return DMatrix
end)

return {
    DynamicArray = DynamicArray,
    DArrayRawType = DArrayRawType,
    DArrayStackBase = DArrayStackBase,
    DArrayVectorBase = DArrayVectorBase,
    DArrayIteratorBase = DArrayIteratorBase,
    DynamicVector = DynamicVector,
    DynamicMatrix = DynamicMatrix
}
