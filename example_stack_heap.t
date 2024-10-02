-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

require("terralibext")
local base = require("base")
local alloc = require("alloc")
local err = require("assert")
local range = require("range")
local io = terralib.includec("stdio.h")

local Allocator = alloc.Allocator

local size_t = uint64

local DynamicStack = terralib.memoize(function(T)

    local S = alloc.SmartBlock(T) --typed memory block
    S:complete() --always complete the implementation of SmartBlock

    local struct stack{
        data : S
        size : size_t
    }
    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concept-based function overloading at compile-time
    base.AbstractBase(stack)

    stack.staticmethods.new = terra(alloc : Allocator, capacity: size_t)
        return stack{alloc:allocate(sizeof(T), capacity), 0}
    end

    terra stack:size()
        return self.size
    end

    terra stack:capacity()
        return self.data:size()
    end

    terra stack:push(v : T)
        if self:size() < self:capacity() then
            self.size = self.size + 1
            self:set(self.size-1, v)
        end
    end

    terra stack:pop()
        if self:size() > 0 then
            self.size = self.size - 1
            return self:get(self.size)
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

    --iterator - behaves like a pointer and can be passed
    --around like a value, convenient for use in ranges.
    local struct iterator{
        parent : &stack
        ptr : &T
    }

    terra stack:getiterator()
        return iterator{self, self.data.ptr}
    end

    terra iterator:getvalue()
        return @self.ptr
    end

    terra iterator:next()
        self.ptr = self.ptr + 1
    end

    terra iterator:isvalid()
        return self.ptr - self.parent.data.ptr < self.parent.size
    end
    
    stack.iterator = iterator
    range.Base(stack, iterator, T)

    return stack
end)

return {
    DynamicStack = DynamicStack
}