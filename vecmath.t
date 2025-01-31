-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

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

local vecmath = {
    ["float"] = {[8] = {}, [16] = {}},
    ["double"] = {[4] = {}, [8] = {}},
}

local func = {
    ["sin"] = 10,
    ["cos"] = 10,
    ["exp"] = 10,
    ["log"] = 10,
    ["sqrt"] = 5,
}

for typ, vmath in pairs(vecmath) do
    for width, _ in pairs(vmath) do
        for name, precision in pairs(func) do
            local prefix = typ:sub(1, 1)
            local vecname = (
                ("%s%s%d_u%02d"):format(name, prefix, width, precision)
            )
            vecmath[typ][width][name] = sleef[vecname]
        end
    end
end

vecmath.has_avx512_support = has_avx512_support
return vecmath
