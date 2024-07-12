local M = {}
local C = terralib.includec("math.h")

--constants
M.pi = constant(3.14159265358979323846264338327950288419716939937510)

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
    exp2 = "exp2",
    log = "log",
    log10 = "log10",
    sqrt = "sqrt",
    cbrt = "cbrt",
    erf = "erf",
    erfc = "erfc",
    gamma = "tgamma",
    loggamma = "lgamma",
    abs = "fabs"
}

local funs_two_var = {
    pow = "pow",
    atan2 = "atan2",
    hypot = "hypot",
    max = "fmax",
    min = "fmin",
    dist = "fdim"
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
    M[tname] = f
end

for tname, cname in pairs(funs_two_var) do
    local f = terralib.overloadedfunction(tname)
    for _, T in ipairs{float,double} do
        local cfun = T==float and C[cname.."f"] or C[cname]
        f:adddefinition(terra(x : T, y : T) return cfun(x, y) end)
    end
    M[tname] = f
end


for tname, cname in pairs(funs_three_var) do
    local f = terralib.overloadedfunction(tname)
    for _, T in ipairs{float,double} do
        local cfun = T==float and C[cname.."f"] or C[cname]
        f:adddefinition(terra(x : T, y : T, z : T) return cfun(x, y, z) end)
    end
    M[tname] = f
end

--convenience functions
local cotf = terra(x : float) return M.cos(x) / M.sin(x) end
local cot  = terra(x : float) return M.cos(x) / M.sin(x) end
M.cot = terralib.overloadedfunction("cot", {cotf, cot})

--comparing functions
M.isapprox = terra(a : double, b : double, atol : double)
    return M.dist(a, b) < atol
end

return M