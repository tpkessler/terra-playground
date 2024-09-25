-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

require("terralibext")
local alloc = require("alloc")
local err = require("assert")
local range = require("range")
local io = terralib.includec("stdio.h")

local Allocator = alloc.Allocator

local size_t = uint64

local DynamicStack = terralib.memoize(function(T)

    local S = alloc.SmartBlock(T) --typed memory block

    local struct stack{
        data : S
        size : size_t
    }

    stack.staticmethods = {}

    stack.staticmethods.new = terra(alloc : Allocator, capacity: size_t)
        return stack{alloc:allocate(sizeof(T), capacity), 0}
    end

    stack.metamethods.__getmethod = function(self, methodname)
        return self.methods[methodname] or stack.staticmethods[methodname]
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
    local struct iter{
        ptr : &T
    }

    terra stack:getfirst()
        return iter{self.data.ptr}
    end

    terra stack:getvalue(iter : &iter)
        return @iter.ptr
    end

    terra stack:next(iter : &iter)
        iter.ptr = iter.ptr + 1
    end

    terra stack:isvalid(iter : &iter)
        return iter.ptr < [&T](self.data.ptr+self.size)
    end
    
    range.Base(stack, iter, T)

    return stack
end)

return {
    DynamicStack = DynamicStack
}