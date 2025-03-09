-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

require("terralibext")
local base = require("base")
local alloc = require("alloc")
local err = require("assert")
local concepts = require("concepts")
local range = require("range")

local Allocator = alloc.Allocator

local size_t = uint64

local StackBase = terralib.memoize(function(stack)

    local T = stack.traits.eltype

	terra stack:reverse()
		var size = self:size()
		for i = 0, size / 2 do
			var a, b = self:get(i), self:get(size -1 - i)
			self:set(i, b)
			self:set(size - 1 - i, a)
		end
	end

    --iterator - behaves like a pointer and can be passed
    --around like a value, convenient for use in ranges.
    local struct iterator{
        parent : &stack
        ptr : &T
    }

    terra stack:getiterator()
        return iterator{self, self:getdataptr()}
    end

    terra iterator:getvalue()
        return @self.ptr
    end

    terra iterator:next()
        self.ptr = self.ptr + 1
    end

    terra iterator:isvalid()
        return self.ptr - self.parent:getdataptr() < self.parent:size()
    end
    
    stack.iterator = iterator
    range.Base(stack, iterator)

end)


local DynamicStack = terralib.memoize(function(T)

    local S = alloc.SmartBlock(T) --typed memory block
    S:complete() --always complete the implementation of SmartBlock

    local struct stack{
        data : S
        size : size_t
    }

    stack.metamethods.__typename = function(self)
        return ("DynamicStack(%s)"):format(tostring(T))
    end

    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concepts-based function overloading at compile-time
    base.AbstractBase(stack)

    stack.traits.eltype = T

    stack.staticmethods.new = terra(alloc : Allocator, capacity: size_t)
        return stack{alloc:new(sizeof(T), capacity), 0}
    end

    stack.staticmethods.frombuffer = terra(n: size_t, ptr: &T)
        return stack{S.frombuffer(n, ptr), n}
    end

    terra stack:getdataptr()
        return self.data:getdataptr()
    end

    terra stack:size()
        return self.size
    end

    terra stack:capacity()
        return self.data:size()
    end

    local io =  terralib.includec("stdio.h")

    terra stack:push(v : T)
        --we don't allow pushing when 'data' is empty
        --[[
        err.assert(self.data:isempty() == false)
        if self:size() == self:capacity() then
            self.data:reallocate(1 + 2 * self:capacity())
        end
        self.size = self.size + 1
        --]]
        --[[
        if v.arg:owns_resource() then
            io.printf("before move: resource is owned\n")
        elseif v.arg:borrows_resource() then
            io.printf("before move: resource is borrowed\n")
        elseif v.arg:isempty() then
            io.printf("before move: resource is empty\n")
        end
        --]]
        escape
            print(v.handle)
        end

        self.data.ptr[self.size - 1] = v
        --[[
        if v.arg:owns_resource() then
            io.printf("after move: resource is owned\n")
        elseif v.arg:borrows_resource() then
            io.printf("after move: resource is borrowed\n")
        elseif v.arg:isempty() then
            io.printf("after move: resource is empty\n")
        end
        --]]
    end
    stack.methods.push:printpretty()


    terra stack:pop()
        if self:size() > 0 then
            var tmp = self:get(self.size - 1)
            self.size = self.size - 1
            return tmp
        end
    end

    terra stack:get(i : size_t)
        err.assert(i < self:size())
        return self.data:get(i)
    end

    terra stack:set(i : size_t, v : T)
        err.assert(i < self:size())
        self.data:set(i, v)
    end

    stack.metamethods.__apply = macro(function(self, i)
        return quote 
            err.assert(i < self:size())
        in
            self.data(i)
        end
    end)

    terra stack:insert(i: size_t, v: T)
        var sz = self:size()
        err.assert(i <= sz)
        self:push(v)
        if i < sz then
            for jj = 0, sz - i do
                var j = sz - 1 - jj
                self(j + 1) = self(j)
            end
            self(i) = v
        end
    end

    --add all methods from stack-base
    StackBase(stack)

    --initialize to empty block
    stack.methods.__init = terra(self : &stack)
        self.data:__init()
        self.size = 0
    end

    terralib.ext.addmissing.__move(stack)
    stack.methods.__copy = stack.methods.__move

    --sanity check
    assert(concepts.DStack(stack), "Stack type does not satisfy the DStack concepts.")

    return stack
end)

return {
    StackBase = StackBase,
    DynamicStack = DynamicStack
}
