local alloc = require("alloc")

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

    return stack
end)

return {
    DynamicStack = DynamicStack
}