-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local base = require("base")
local concept = require("concept")
local vecbase = require("vector")
local veccont = require("vector_contiguous")
local vecblas = require("vector_blas")
local range = require("range")
local err = require("assert")

local io = terralib.includec("stdio.h")

local Allocator = alloc.Allocator
local size_t = uint64

local DynamicVector = terralib.memoize(function(T)
    local S = alloc.SmartBlock(T)
    S:complete()

    local struct V{
        data: S
        inc: size_t
    }
    V.eltype = T

    function V.metamethods.__typename(self)
        return ("DynamicVector(%s)"):tostring(T)
    end

    base.AbstractBase(V)

    terra V:size()
        return self.data:size()
    end

    terra V:get(i: size_t)
        return self.data:get(self.inc * i)
    end

    terra V:set(i: size_t, a: T)
        return self.data:set(self.inc * i, a)
    end

    V.metamethods.__apply = macro(function(self, i)
        return `self.data(self.inc * i)
    end)

    vecbase.VectorBase(V)

    terra V:getbuffer()
        err.assert(self.inc == 1)
        return self:size(), self.data.ptr 
    end

    veccont.VectorContiguous:addimplementations{V}

    V.staticmethods.new = terra(alloc: Allocator, size: size_t)
        var vec : V
        vec.data = alloc:allocate(sizeof(T), size) 
        vec.inc = 1
        return vec
    end

    V.staticmethods.like = terra(alloc: Allocator, w: &V)
        return V.new(alloc, w:size())
    end

    V.staticmethods.all = terra(alloc: Allocator, size: size_t, value: T)
        var v = V.new(alloc, size)
        for i = 0, size do
            v:set(i, value)
        end
        return v
    end

    V.staticmethods.zeros = terra(alloc: Allocator, size: size_t)
        return V.all(alloc, size, 0)
    end

    V.staticmethods.ones = terra(alloc : Allocator, size : size_t)
        return V.all(alloc, size, 1)
    end

    V.staticmethods.zeros_like = terra(alloc: Allocator, w: &V)
        return V.zeros(alloc, w:size())
    end

    V.staticmethods.ones_like = terra(alloc: Allocator, w: &V)
        return V.ones(alloc, w:size())
    end

    V.staticmethods.from = macro(
        function(allocator, ...)
            local args = {...}
            local size = #args
            local vec = symbol(V)
            local set_values = terralib.newlist()
            for i, v in ipairs(args) do
                set_values:insert(quote [vec]:set(i - 1, v) end)
            end
            return quote
                var [vec] = V.new(allocator, size)
                [set_values]     
            in
                [vec]
            end
        end)

    if concept.BLASNumber(T) then
        terra V:getblasinfo()
            var n = self:size()
            var data = self.data.ptr
            var inc = self.inc
            return n, data, inc
        end

        vecblas.VectorBLASBase(V)
    end

    terra V:getiterator()
        return self.data:getiterator()
    end
    
    range.Base(V, S.iterator_t, T)

    return V
end)

return {
    DynamicVector = DynamicVector
}
