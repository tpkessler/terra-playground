-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT
--

local function has_avx512_support()
    local cpuinfo = assert(io.popen("grep avx512f /proc/cpuinfo"))
    local ret = cpuinfo:read("*a")
    cpuinfo:close()
    return ret ~= ""
end

local sleef = setmetatable(
    terralib.includec(
        "./build-sleef/include/sleef.h",
        {has_avx512_support() and "-D__AVX512F__" or "-D__AVX2__"}
    ),
    {
        __index = function(self, name)
            return rawget(self, "Sleef_" .. name) or rawget(self, name)
        end
    }
)
local ext = (require("ffi").os == "Linux" and ".so" or ".dylib")
terralib.linklibrary("./build-sleef/lib/libsleef" .. ext)

local C = terralib.includec("stdio.h")
terra main()
    var x = vectorof(double, 1, 2, 3, 4, 5, 6, 7, 8)
    var y = sleef.finz_sind8_u10avx512f(x)
    C.printf(
        "%g %g %g %g %g %g %g %g\n",
        y[0], y[1], y[2], y[3], y[4], y[5], y[6], y[7]
    )
    return 0
end
main:printpretty()
main()
