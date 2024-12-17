-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"

local math = {}
local C = terralib.includecstring[[
    #include <stdlib.h>
    #include <math.h>
    #include <tgmath.h>
]]
local concepts = require("concepts")
--constants
math.pi = constant(3.14159265358979323846264338327950288419716939937510)

function float:eps() return 0x1p-23 end
function double:eps() return 0x1p-52 end

local funs = {
    sin = "sin",
    cos = "cos",
    tan = "tan",
    asin = "asin",
    acos = "acos",
    atan = "atan",
    sinh = "sinh",
    cosh = "cosh",
    tanh = "tanh",
    asinh = "asinh",
    acosh = "acosh",
    atanh = "atanh",
    exp = "exp",
    expm1 = "expm1",
    exp2 = "exp2",
    log = "log",
    log1p = "log1p",
    log10 = "log10",
    sqrt = "sqrt",
    cbrt = "cbrt",
    erf = "erf",
    erfc = "erfc",
    gamma = "tgamma",
    loggamma = "lgamma",
    abs = "fabs",
    floor = "floor",
    ceil = "ceil",
    round = "round",
    j0 = "j0",
    j1 = "j1",
    jn = "jn",
    pow = "pow",
    atan2 = "atan2",
    hypot = "hypot",
    fmod = "fmod",
    fusedmuladd = "fma",
}

for tname, cname in pairs(funs) do
    local f = terralib.overloadedfunction(tname)
    for _, T in ipairs{float,double} do
        local cfun = (T == float and C[cname.."f"] or C[cname])
        local sig = cfun.type
        local arg = sig.parameters
        local sym = arg:map(function(T) return symbol(T) end)
        local impl = terra([sym]) return cfun([sym]) end
        impl:setinlined(true)
        f:adddefinition(impl)
    end
    math[tname] = f
end

math.beta = terralib.overloadedfunction("beta")
for _, T in ipairs{float,double} do
    math.beta:adddefinition(
        terra(x : T, y : T) : T
            return math.gamma(x) * math.gamma(y) / math.gamma(x + y)
        end
    )
end

--add some missing defintions
math.abs:adddefinition(terra(x : int) return C.abs(x) end)
math.abs:adddefinition(terra(x : int64) return C.labs(x) end)


math.sign = terralib.overloadedfunction("sign")
for _, T in pairs({int32, int64, float, double}) do
    math.sign:adddefinition(
        terra(x: T): T
            return terralib.select(x < 0, -1, 1)
        end
    )
end

--convenience functions
local cotf = terra(x : float) return math.cos(x) / math.sin(x) end
local cot  = terra(x : double) return math.cos(x) / math.sin(x) end
math.cot = terralib.overloadedfunction("cot", {cotf, cot})
math.ldexp = terralib.overloadedfunction("ldexp", {C.ldexp, C.ldexpf})

--min and max
math.min = terralib.overloadedfunction("min")
math.max = terralib.overloadedfunction("max")
for _, T in ipairs{int32, int64, float, double} do
    math.min:adddefinition(terra(x : T, y : T) return terralib.select(x < y, x, y) end)
    math.max:adddefinition(terra(x : T, y : T) return terralib.select(x > y, x, y) end)
end

terraform math.dist(a: T, b: T) where {T: concepts.Number}
    return math.abs(a - b)
end

-- comparing functions
terraform math.isapprox(a: T, b: T, atol: S)
    where {T: concepts.Any, S: concepts.Any}
    return math.dist(a, b) < atol
 end

for _, name in pairs({"real", "imag", "conj"}) do
    math[name] = terralib.overloadedfunction(name)
    for _, T in ipairs{int32, int64, float, double} do
        local impl
        if name == "imag" then
            impl = terra(x: T) return [T](0) end
        else
            impl = terra(x: T) return x end
        end
        math[name]:adddefinition(impl)
    end
end

return math
