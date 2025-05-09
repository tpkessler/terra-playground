-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local T = double
local N = 32
local SIMD = vector(T, N)

local uintptr_t = terralib.includec("stdint.h").uintptr_t
local terra vecload(data: &T)
    -- Only cast to SIMD vector if the data is properly aligned.
    -- SSE/AVX types are very strict on this. The chosen 64 refers
    -- to 64 * 8 == 512 bits, currently the largest supported
    -- vector length (with AVX 512). The correct alignment can be
    -- passed an argument to most allocators.
    if [uintptr_t](data) % [uintptr_t](64) == 0 then
        return @[&SIMD](data)
    else
        escape
            local arg = terralib.newlist()                        
            for i = 0, N - 1 do
                arg:insert(`data[i])
            end
            emit quote return vectorof(T, [arg]) end
        end
    end
end
vecload:disas()

local terra hsum(v: SIMD)
    var res = [T](0)
    escape
        for i = 0, N - 1 do
            emit quote res = res + v[i] end
        end
    end
    return res
end
-- hsum:disas()
