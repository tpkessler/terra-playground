local alloc = require("alloc")
local interface = require("interface")
local stack = require("stack")
local err = require("assert")

local Allocator = alloc.Allocator
local size_t = uint64


local VectorBase = terralib.memoize(function(V, T)

    V.eltype = T
    rawset(V, "staticmethods", {})

    V.metamethods.__getmethod = function(self, methodname)
        return self.methods[methodname] or self.staticmethods[methodname]
    end

    terra V:size()
        return self.data:size()
    end

    terra V:get(i : size_t)
        return self.data:get(i)
    end

    terra V:set(i : size_t, v : T)
        self.data:set(i, v)
    end

    V.staticmethods.new = terra(alloc : Allocator, size : size_t)
        return V{alloc:allocate(sizeof(T), size)}
    end

    V.staticmethods.fill = terra(alloc : Allocator, size : size_t, value : T)
        var v = V.new(alloc, size)
        for i = 0, size do
            v:set(i, value)
        end
        return v
    end

    V.staticmethods.zeros = terra(alloc : Allocator, size : size_t)
        return V.fill(alloc, size, 0)
    end

    V.staticmethods.ones = terra(alloc : Allocator, size : size_t)
        return V.fill(alloc, size, 1)
    end

    V.staticmethods.from = macro(
        function(allocator, ...)
            local args = {...}
            local size = #args
            local vec = symbol(V)
            local set_values = terralib.newlist()
            for i, v in ipairs(args) do
                set_values:insert(quote [vec]:set(i-1, v) end)
            end

            return quote
                var [vec] = V.new(allocator, size)
                   [set_values]     
            in
                [vec]
            end
        end
    )

    terra V:dot(x : V)
		err.assert(self:size() == x:size())
        var size = self:size()
        var res : T = 0
        for i = 0, size do
            res = res + self:get(i) * x:get(i)
        end
        return res
    end

    terra V:sum()
		var res : T = 0
        for i = 0, self:size() do
            res = res + self:get(i)
        end
        return res
    end

    terra V:map(alloc : Allocator, f : {T} -> T)
        var size = self:size()
        var v = V.new(alloc, size)
        for i = 0, size do
            v:set(i, f(self:get(i)))
        end
        return v
    end

    return V
end)


local DynamicVector = terralib.memoize(function(T)

    local S = alloc.SmartBlock(T)

    local Base = function(V) VectorBase(V,T) end

    local struct vector(Base){
        data: S
    }

    return vector
end)

return {
    DynamicVector = DynamicVector
}