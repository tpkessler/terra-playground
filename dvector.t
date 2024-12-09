-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local base = require("base")
local concepts = require("concepts")
local stack = require("stack")
local vecbase = require("vector")
local veccont = require("vector_contiguous")
local vecblas = require("vector_blas")
local range = require("range")
local err = require("assert")

local Allocator = alloc.Allocator
local size_t = uint64

local DynamicVector = terralib.memoize(function(T)
    local S = alloc.SmartBlock(T)
    S:complete()

    local struct V{
        data: S
        size: size_t
        inc: size_t
    }
    V.eltype = T

    function V.metamethods.__typename(self)
        return ("DynamicVector(%s)"):tostring(T)
    end

    base.AbstractBase(V)

    terra V:getdataptr()
        return self.data:getdataptr()
    end

    terra V:size()
        return self.size
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

    V.staticmethods.new = terra(alloc: Allocator, size: size_t)
        var vec : V
        vec.data = alloc:allocate(sizeof(T), size)
        vec.size = size
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

    local dstack = stack.DynamicStack(T)

    V.metamethods.__cast = function(from, to, exp)
        if from == dstack and to == V then
            --only allow rvalues to be cast from a dstack to a dvector
            --a dynamic stack can reallocate, which makes it unsafe to cast
            --an lvalue since the lvalue may be modified (reallocate) later
            if not exp:islvalue() then
                return quote
                    var tmp = exp
                    var v : V
                    v.data = tmp.data:__move() --we move the resources over
                    v.size = tmp.size --as size we provide the whole resource
                    v.inc = 1
                in
                    v
                end
            end
        else
            error("ArgumentError: not able to cast " .. tostring(from) .. " to " .. tostring(to) .. ".")
        end
    end

    if concepts.BLASNumber(T) then
        terra V:getblasinfo()
            var n = self:size()
            var data = self.data.ptr
            var inc = self.inc
            return n, data, inc
        end

        vecblas.VectorBLASBase(V)
    end

    local struct iterator{
        -- Reference to vector over which we iterate.
        -- It's used to check the length of the iterator
        parent: &V
        -- Reference to the current element held in the smart block
        ptr: &T
    }

    terra V:getiterator()
        return iterator {self, self.data.ptr}
    end

    terra iterator:getvalue()
        return @self.ptr
    end

    terra iterator:next()
        self.ptr = self.ptr + self.parent.inc
    end

    terra iterator:isvalid()
        return (self.ptr - self.parent.data.ptr) < self.parent.size * self.parent.inc
    end

    range.Base(V, iterator)

    return V
end)

return {
    DynamicVector = DynamicVector
}
