-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local concepts = require("concepts")

local tmath = {}
local C = terralib.includecstring[[
    #include <stdio.h>
    #include <stdlib.h>
    #include <math.h>
    #include <tgmath.h>
]]
local concepts = require("concepts")
--constants
tmath.pi = constant(3.14159265358979323846264338327950288419716939937510)

function float:eps() return constant(float, 0x1p-23) end
function double:eps() return constant(double, 0x1p-52) end

for _,T in ipairs({float, double, int8, int16, int32, int64, uint8, uint16, uint32, uint64}) do
    function T:zero()
        return constant(T, 0)
    end
    function T:unit()
        return constant(T, 1)
    end
end

local funs_single_var = {
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
    round = "round"
}

local funs_two_var = {
    pow = "pow",
    atan2 = "atan2",
    hypot = "hypot",
    fmod = "fmod"
}

local funs_three_var = {
    fusedmuladd = "fma"
}

for tname, cname in pairs(funs_single_var) do
    local f = terralib.overloadedfunction(tname)
    for _, T in ipairs{float,double} do
        local cfun = T==float and C[cname.."f"] or C[cname]
        f:adddefinition(terra(x : T) return cfun(x) end)
    end
    tmath[tname] = f
end

for tname, cname in pairs(funs_two_var) do
    local f = terralib.overloadedfunction(tname)
    for _, T in ipairs{float,double} do
        local cfun = T==float and C[cname.."f"] or C[cname]
        f:adddefinition(terra(x : T, y : T) return cfun(x, y) end)
    end
    tmath[tname] = f
end

for tname, cname in pairs(funs_three_var) do
    local f = terralib.overloadedfunction(tname)
    for _, T in ipairs{float,double} do
        local cfun = T==float and C[cname.."f"] or C[cname]
        f:adddefinition(terra(x : T, y : T, z : T) return cfun(x, y, z) end)
    end
    tmath[tname] = f
end

tmath.beta = terralib.overloadedfunction("beta")
for _, T in ipairs{float,double} do
    tmath.beta:adddefinition(
        terra(x : T, y : T) : T
            return tmath.gamma(x) * tmath.gamma(y) / tmath.gamma(x+y)
        end
    )
end

--add some missing defintions
tmath.abs:adddefinition(terra(x : int) return C.abs(x) end)
tmath.abs:adddefinition(terra(x : int64) return C.labs(x) end)


tmath.sign = terralib.overloadedfunction("sign")
for _, T in pairs({int32, int64, float, double}) do
    tmath.sign:adddefinition(
        terra(x: T): T
            return terralib.select(x < 0, -1, 1)
        end
    )
end

--convenience functions
local cotf = terra(x : float) return tmath.cos(x) / tmath.sin(x) end
local cot  = terra(x : double) return tmath.cos(x) / tmath.sin(x) end
tmath.cot = terralib.overloadedfunction("cot", {cotf, cot})
tmath.ldexp = terralib.overloadedfunction("ldexp", {C.ldexp, C.ldexpf})

--min and max
tmath.min = terralib.overloadedfunction("min")
tmath.max = terralib.overloadedfunction("max")
for _, T in ipairs{int32, int64, float, double} do
    tmath.min:adddefinition(terra(x : T, y : T) return terralib.select(x < y, x, y) end)
    tmath.max:adddefinition(terra(x : T, y : T) return terralib.select(x > y, x, y) end)
end

terraform tmath.dist(a: T, b: T) where {T: concepts.Number}
    return tmath.abs(a - b)
end

-- comparing functions
terraform tmath.isapprox(a: T, b: T, atol: S)
    where {T: concepts.Any, S: concepts.Any}
    return tmath.dist(a, b) < atol
 end

for _, name in pairs({"real", "imag", "conj"}) do
    tmath[name] = terralib.overloadedfunction(name)
    for _, T in ipairs{int32, int64, float, double} do
        local impl
        if name == "imag" then
            impl = terra(x: T) return [T](0) end
        else
            impl = terra(x: T) return x end
        end
        tmath[name]:adddefinition(impl)
    end
end

--determine the number of digits in representing a number of n bytes.
tmath.ndigits = function(nbytes)
    return math.ceil(8 * nbytes * (math.log(2) / math.log(10)))
end

local numtostr = terralib.overloadedfunction("numtostr")
numtostr.format = {}
--add implementations of numtostr
--globals are used to change the format
for _,T in ipairs{float, double, int8, int16, int32, int64, uint8, uint16, uint32, uint64} do
    --add format for each type
    if concepts.Float(T) then
        numtostr.format[T] = global(rawstring, "%0.2f")
    elseif concepts.Integer(T) then
        numtostr.format[T] = global(rawstring, "%d")
    else
        error("Please specify a format for this type.")
    end
    --length of static buffer
    --+1 for sign
    --+1 for /0 terminating character
    local maxlen = tmath.ndigits(sizeof(T)) + 1 + 1
    --format of number type T
    local format = numtostr.format[T]
    numtostr:adddefinition(
        terra(v : T)
            var buffer : int8[maxlen]
            C.snprintf(buffer, maxlen, format, v)
            return buffer
        end
    )
end
--add to tmath namespace
tmath.numtostr = numtostr

return tmath
