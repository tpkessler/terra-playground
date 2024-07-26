local io = terralib.includec("stdio.h")
local base = require("vector_base")
local err = require("assert")

local size_t = uint64

local StackBase = terralib.memoize(function(S, T, N)

    S.eltype = T

    S.methods.size = terra(self : &S) : size_t
        return N
    end

    S.methods.get = terra(self : &S, i : size_t) : T
        err.assert(i < N)
        return self.data[i]
    end

    S.methods.set = terra(self : &S, i : size_t, value : T)
        err.assert(i < N)
        self.data[i] = value
    end

    S.metamethods.__apply = macro(function(self, i)
        return quote
            err.assert(i < N)
        in
            self.data[i]
        end
    end)

    return S
end)

local VectorBase = terralib.memoize(function(V, T, N)

    --add all functionality of StackBase
    StackBase(V,T,N)

    V.staticmethods = {}

    V.metamethods.__getmethod = function(self, methodname)
        return self.methods[methodname] or V.staticmethods[methodname]
    end

    V.staticmethods.new = terra()
        return V{}
    end

    V.staticmethods.fill = terra(value : T)
        var v = V.new()
        for i=0,N do
            v.data[i] = value
        end
        return v
    end

    V.staticmethods.zeros = terra()
        return V.fill(0)
    end

    V.staticmethods.ones = terra()
        return V.fill(1)
    end

    V.staticmethods.from = macro(
        function(...)
            local args = {...}
            assert(#args == N, "Length of input list does not match static dimension")
            local vec = symbol(V)
            local set_values = terralib.newlist()
            for i, v in ipairs(args) do
                set_values:insert(quote [vec].data[i - 1] = v end)
            end
            return quote
                var [vec] = V.new()
                [set_values]
            in
                [vec]
            end
        end
    )

    return V
end)

local StaticVector = terralib.memoize(function(T, N)
    
    local Base = function(V) VectorBase(V,T,N) end

    local struct vec(Base){
        data : T[N]
    }

    return vec
end)

return {
    StaticVector = StaticVector
}