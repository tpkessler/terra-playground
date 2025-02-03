-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"

local function has_avx512_support()
    if require("ffi").os ~= "Linux" then
        return false
    else
        local cpuinfo = assert(io.popen("grep avx512f /proc/cpuinfo"))
        local ret = cpuinfo:read("*a")
        cpuinfo:close()
        return (ret ~= "")
    end
end

local sleef = setmetatable(
    terralib.includec(
        "./build-sleef/include/sleef.h",
        {"-D__AVX512F__ -D__AVX2__ -D__AVX__"}
    ),
    {
        __index = function(self, name)
            return (
                rawget(self, "Sleef_" .. name)
                or rawget(self, name)
                or error("Symbol " .. name .. " not found")
            )
        end
    }
)
local ext = (require("ffi").os == "Linux" and ".so" or ".dylib")
terralib.linklibrary("./build-sleef/lib/libsleef" .. ext)

-- SSE and AArch64
local supported_width = terralib.newlist({128})
if require("ffi").arch == "x64" then
    -- AVX/AVX2
    supported_width:insert(256)
    if has_avx512_support() then
        supported_width:insert(512)
    end
end
supported_width = supported_width:rev()
local vecmath = {[float] = {}, [double] = {}}

local func = {
    ["sin"] = 10,
    ["cos"] = 10,
    ["exp"] = 10,
    ["log"] = 10,
    ["sqrt"] = 5,
}

for T, _ in pairs(vecmath) do
    for name, precision in pairs(func) do
        local prefix = tostring(T):sub(1, 1)
        vecmath[T][name] = {}
        for _, width in ipairs(supported_width) do
            local len = width / (8 * sizeof(T))
            local vecname = (
                ("%s%s%d_u%02d"):format(name, prefix, len, precision)
            )
            vecmath[T][name][width] = sleef[vecname]
        end
    end
end

local unroll_math = function(T, N, M, func, x, y)
    local stat = terralib.newlist()
    local SIMD = vector(T, M)
    local xp = symbol(&SIMD)
    local yp = symbol(&SIMD)
    stat:insert(quote var [xp] = [&SIMD](&[x]) end)
    stat:insert(quote var [yp] = [&SIMD](&[y]) end)
    local Nr = N / M
    for i = 1, Nr do
        stat:insert(quote @[yp] = [func](@[xp]) end)
        stat:insert(quote [xp] = [xp] + 1 end)
        stat:insert(quote [yp] = [yp] + 1 end)
    end
    return stat
end

local MAX_POW2 = 7

for name, _ in pairs(func) do
    vecmath[name] = terralib.overloadedfunction("vec" .. name)
    for _, T in pairs{float, double} do
        local start = (T == double and 1 or 2)
        for K = start, MAX_POW2 do
            local N = 2 ^ K
            local V = vector(T, N)
            local x = symbol(V)
            local y = symbol(V)
            vecmath[name]:adddefinition(
                terra([x])
                    var [y]
                    escape
                        for _, width in ipairs(supported_width) do
                            local M = width / (8 * sizeof(T))
                            if N % M == 0 then
                                local func = vecmath[T][name][width]
                                local stat = unroll_math(T, N, M, func, x, y)
                                emit quote [stat] end
                                break
                            end
                        end
                    end
                    return [y]
                end
            )
        end
    end
end

terraform vecmath.abs(x: V) where {V}
    return terralib.select(x < 0, -x, x)
end

vecmath.has_avx512_support = has_avx512_support
vecmath.MAX_POW2 = MAX_POW2
return vecmath
