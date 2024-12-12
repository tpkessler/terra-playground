-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local io = terralib.includec("stdio.h")
local err = require("assert")
local alloc = require("alloc")
local base = require("base")
local tmath = require("mathfuns")
local concepts = require("concepts")
local array = require("arraybase")
local vecbase = require("vector")
--local matbase = require("matrix")
local tup = require("tuple")
local range = require("range")

local luafun = require("fun")

local Allocator = alloc.Allocator
local size_t = uint64

--global flag to perform boundscheck
__boundscheck__ = true


local DArrayRawType = function(T, Dimension, options)

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

    --add base functionality
    base.AbstractBase(Array)

    --global type traits
    Array.traits.eltype = T
    Array.traits.ndims = Dimension
    Array.traits.perm = Perm

    return Array
end

local DArrayStackBase = function(Array)

    local T = Array.traits.eltype
    local N = Array.traits.ndims

    terra Array:length() : size_t
        return self.cumsize[ [N-1] ]
    end
    
    Array.methods.data = macro(function(self, i)
        return `self.data(i)
    end)

    --element size as a terra method
    Array.methods.size = terralib.overloadedfunction("size", {
        terra(self : &Array, i : size_t)
            return self.size[i]
        end,
        terra(self : &Array)
            return self.size
        end
    })

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
    local new = terra(alloc: Allocator, size : tup.ntuple(size_t, N))
        var __size = [ &size_t[N] ](&size)  --we need the size as an array
        var cumsize = getcumsize(@__size)   --compute cumulative sizes
        var length = cumsize[N-1]           --length is last entry in 'cumsum'
        return Array{alloc:allocate(sizeof(T), length), @__size, cumsize}
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

end

local DArrayVectorBase = function(Array)

    local T = Array.traits.eltype
    local N = Array.traits.ndims
    local Sizes = tup.ntuple(size_t, N)

    vecbase.VectorBase(Array) --add fall-back routines

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
    vecbase.IteratorBase(Array) --add fall-back routines
 
end

local DynamicArray = function(T, Dimension, options)
    
    --generate the raw type
    local Array = DArrayRawType(T, Dimension, options)
    
    --print typename
    function Array.metamethods.__typename(self)
        local sizes = "{"
        local perm = "{"
        for i = 1, Array.traits.ndims-1 do
            perm = perm .. tostring(Array.traits.perm[i]) .. ","
        end
        perm = perm .. tostring(Array.traits.perm[Array.traits.ndims]) .. "}"
        return "DynamicArray(" .. tostring(T) ..", " .. tostring(Array.traits.ndims) .. ", perm = " .. perm .. ")"
    end

    --implement interfaces
    DArrayStackBase(Array)
    DArrayVectorBase(Array)
    --DArrayIteratorBase(Array)

    return Array
end


return {
    DArrayRawType = DArrayRawType,
    DArrayStackBase = DArrayStackBase,
    DArrayIteratorBase = DArrayIteratorBase,
    DynamicArray = DynamicArray,
    --DynamicVector = DynamicVector,
    --DynamicMatrix = DynamicMatrix
}