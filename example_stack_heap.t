local alloc = require("alloc")
local range = require("range")

local Allocator = alloc.Allocator

local size_t = uint64

local DynamicStack = terralib.memoize(function(T)

    local S = alloc.SmartBlock(T)

    local struct stack{
        data: S
    }

    stack.staticmethods = {}

    stack.staticmethods.new = terra(alloc : Allocator, size: size_t)
        return stack{alloc:allocate(sizeof(T), size)}
    end

    stack.metamethods.__getmethod = function(self, methodname)
        return self.methods[methodname] or stack.staticmethods[methodname]
    end

    terra stack:size()
        return self.data:size()
    end

    terra stack:get(i : size_t)
        return self.data:get(i)
    end

    terra stack:set(i : size_t, v : T)
        self.data:set(i, v)
    end

    stack.methods.getfirst = macro(function(self)
        return quote
        in
            0, self:get(0)
        end
    end)

    stack.methods.getnext = macro(function(self, state)
        return quote 
            state = state + 1
            var value = self:get(state)
        in
            value
        end
    end)

    stack.methods.islast = macro(function(self, state)
        return quote 
            var terminate = (state+1 == self:size())
        in
            terminate
        end
    end)
    
    range.Base(stack, T)

    return stack
end)

return {
    DynamicStack = DynamicStack
}