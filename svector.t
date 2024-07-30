local err = require("assert")
local base = require("base")
local vecbase = require("vector_base")
local concept = require("concept")

local StaticVector = terralib.memoize(function(T, N)
    local function create_static_vector(T, N)
        if T:isprimitive() then
            local nbytes = sizeof(T) * N
            if nbytes < 64 then
                N = 64 / sizeof(T)
            end
            local SIMD = vector(T, N)
            local M = sizeof(SIMD) / sizeof(T)
            local struct V(base.AbstractBase){
                union {
                    data: T[M]
                    simd: SIMD
                }
            }
            return V
        else
           local struct V(base.AbstractBase){
                data: T[N]
            }
            return V
        end
    end

    local V = create_static_vector(T, N)
    V.name = string.format("StaticVector(%s, %d)", tostring(T), N)
    V.eltype = T

    V.metamethods.__typename = function(self)
        return V.name
    end

    terra V:size(): uint64
        return N
    end

    terra V:get(i: uint64)
        err.assert(i < N)
        return self.data[i]
    end

    terra V:set(i: uint64, x: T)
        err.assert(i < N)
        self.data[i] = x
    end


    V.staticmethods.new = terra()
        return V {}
    end

    V.staticmethods.fill = terra(value: T)
        var v = V.new()
        escape
            for i = 0, N - 1 do
                emit quote v.data[i] = value end
            end
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

    vecbase.VectorBase(V, T)

    if T:isprimitive() then
        V.templates.axpy[{V.SelfPtr, concept.Number, V.Self + V.SelfPtr} -> {}] =
            function(V1, S, V2)
                print("Calling special vector implementation")
                local terra axpy(y: V1, a: S, x: V2)
                    y.simd = y.simd + a * x.simd
                end
                return axpy
            end
    end

    return V
end)

return {
    StaticVector = StaticVector
}
