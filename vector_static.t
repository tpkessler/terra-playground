local base = require("vector_base")
local err = require("assert")
local VectorHeap = require("vector_heap")

local VectorStatic = function(T, N)
    local SIMD = vector(T, N)
    local VectorHeap = VectorHeap(T)

    local struct vector{
        union{
            data: T[N]
            simd: SIMD
        }
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

    terra vector:data()
        return &self.data[0]
    end

    terra vector:scal(a: T)
        self.simd = a * self.simd
    end

    terra vector:axpy(a: T, x: &vector)
        self.simd = self.simd + a * x.simd
    end

    terra vector:asheap()
        return VectorHeap.frombuffer(self:size(), self:data(), 1)
    end

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

    local static_methods = {
        new = new,
        from = from
    }

    vector.metamethods.__getmethod = function(Self, method)
        return vector.methods[method] or static_methods[method]
    end

    return vector
end

VectorStatic = terralib.memoize(VectorStatic)

return {
    VectorStatic = VectorStatic
}
