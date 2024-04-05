local base = require("vector_base")
local err = require("assert")

local VectorStatic = function(T, N)

    local struct vector{
        data: T[N]
    }

    local terra new()
        return vector {}
    end

    terra vector:size(): int64
        return N
    end

    terra vector:get(i: int64)
        err.assert(i >= 0)
        err.assert(i < self:size())

        return self.data[i]
    end

    terra vector:set(i: int64, a: T)
        err.assert(i >= 0)
        err.assert(i < self:size())

        self.data[i] = a
    end

    vector = base.VectorBase(vector, T, int64)

    local from = macro(function(...)
        local arg = {...}
        assert(#arg == N,
               "Length of input list does not match static dimension")
        local vec = symbol(vector)
        local set = terralib.newlist()
        for i, v in ipairs(arg) do
            set:insert(quote [vec].data[i - 1] = v end)
        end
        return quote
                   var [vec] = new()
                   [set]
               in
                   [vec]
            end
    end)

    return {
        type = vector,
        new = new,
        from = from
    }
end

VectorStatic = terralib.memoize(VectorStatic)

return VectorStatic
