-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local parametrized = require("parametrized")

local VectorFactory = parametrized.type(function(T, N)
    local SIMD = vector(T, N)
    local struct vec {
        data: SIMD
    }
    terra vec:load(data: &T)
        escape
            local arg = terralib.newlist()                        
            for i = 0, SIMD.N - 1 do
                arg:insert(`data[i])
            end
            emit quote self.data = vectorof(T, [arg]) end
        end
    end
    vec.methods.load:setinlined(true)

    terra vec:store(data: &T)
        escape
            for i = 0, SIMD.N - 1 do
                emit quote data[i] = self.data[i] end
            end
        end
    end
    vec.methods.store:setinlined(true)

    terra vec:hsum()
        var res = [T](0)
        escape
            for j = 0, N - 1 do
                emit quote res = res + self.data[j] end
            end
        end
        return res
    end
    vec.methods.hsum:setinlined(true)

    function vec.metamethods.__cast(from, to, exp)
        if from == T or from == SIMD then
            return `vec {[exp]}
        elseif from == &T then
            return quote
                var v: vec
                v:load([exp])
            in
                v
            end
        end
        error("Cannot convert non vector type to vector")
    end

    terra vec.metamethods.__add(self: vec, other: vec)
        return vec {self.data + other.data}
    end

    terra vec.metamethods.__sub(self: vec, other: vec)
        return vec {self.data - other.data}
    end

    terra vec.metamethods.__ne(self: vec)
        return vec {-self.data}
    end

    terra vec.metamethods.__mul(self: vec, other: vec)
        return vec {self.data * other.data}
    end

    terra vec.metamethods.__div(self: vec, other: vec)
        return vec {self.data / other.data}
    end

    return vec
end)

return {
    VectorFactory = VectorFactory,
}
