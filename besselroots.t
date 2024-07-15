local svector = require("svector")
local dvector = require('dvector')
local math = require("mathfuns")
local poly = require("poly")
local alloc = require('alloc')
local io = terralib.includec("stdio.h")

local size_t = uint64
local Allocator = alloc.Allocator
local dvec = dvector.DynamicVector(double)

local Module = {}

local besselj0_roots = terra()
    return arrayof(double,
        2.4048255576957728,
        5.5200781102863106,
        8.6537279129110122,
        11.791534439014281,
        14.930917708487785,
        18.071063967910922,
        21.211636629879258,
        24.352471530749302,
        27.493479132040254,
        30.634606468431975,
        33.775820213573568,
        36.917098353664044,
        40.058425764628239,
        43.199791713176730,
        46.341188371661814,
        49.482609897397817,
        52.624051841114996,
        55.765510755019979,
        58.906983926080942,
        62.048469190227170
    )
end


local besselj1_on_besselj0_roots = terra()
    return arrayof(double,
        0.2695141239419169,
        0.1157801385822037,
        0.07368635113640822,
        0.05403757319811628,
        0.04266142901724309,
        0.03524210349099610,
        0.03002107010305467,
        0.02614739149530809,
        0.02315912182469139,
        0.02078382912226786
    )
end

local poly1 = poly.Polynomial(double, 2)
local poly2 = poly.Polynomial(double, 3)
local poly3 = poly.Polynomial(double, 4)
local poly4 = poly.Polynomial(double, 5)

terra Module.bessel_zero_roots(alloc : Allocator, m : size_t)
    --bessel0roots roots of besselj(0,x). Use asymptotics.
    --Use McMahon's expansion for the remainder (NIST, 10.21.19):
    var jk = dvec.new(alloc, m)
    var c = arrayof(double, 1071187749376. / 315., 0.0, -401743168. / 105., 0.0, 120928. / 15., 0.0, -124. / 3., 0.0, 1.0, 0.0)
    var p2 = poly2.from(1.0, c[6], c[4])
    var p3 = poly3.from(1.0, c[6], c[4], c[2])
    --First 20 are precomputed:
    var jk_0_20 = besselj0_roots()
    for jj = 0, math.min(m, 20) do
        jk(jj) = jk_0_20[jj]
    end
    for jj = 20, math.min(m, 47) do
        var ak = math.pi * (jj+1. - .25)
        var ak82 = math.pow(.125 / ak, 2)
        jk(jj) = ak + .125 / ak * p3(ak82)
    end
    for jj = 47, math.min(m, 344) do
        var ak = math.pi * (jj+1. - .25)
        var ak82 = math.pow(.125 / ak, 2)
        jk(jj) = ak + .125 / ak * p2(ak82)
    end    
    return jk
end

terra Module.besselJ1(alloc : Allocator, m : size_t)
    --besselj1 evaluate besselj(1,x)^2 at the roots of besselj(0,x)
    --use asymptotics. Use Taylor series of (NIST, 10.17.3) and McMahon's
    --expansion (NIST, 10.21.19)
    var Jk2 = dvec.new(alloc, m)
    var c = arrayof(double, -171497088497. / 15206400., 461797. / 1152., -172913. / 8064., 151. / 80., -7. / 24., 0.0, 2.0)
    var p1 = poly1.from(c[4], c[3])
    var p2 = poly2.from(c[4], c[3], c[2])
    var p3 = poly3.from(c[4], c[3], c[2], c[1])
    var p4 = poly4.from(c[4], c[3], c[2], c[1], c[0])
    --first 10 are precomputed:
    var jk2_0_9 = besselj1_on_besselj0_roots()
    for jj = 0, math.min(m, 10) do
        Jk2(jj) = jk2_0_9[jj]
    end
    for jj = 10, math.min(m, 15) do
        var ak = math.pi * (jj+1. - .25)
        var ak2 = math.pow(1. / ak, 2)
        Jk2(jj) = 1. / (math.pi * ak) * math.fusedmuladd(p4(ak2), math.pow(ak2,2), c[6])
    end
    for jj = 15, math.min(m, 21) do
        var ak = math.pi * (jj+1. - .25)
        var ak2 = math.pow(1. / ak, 2)
        Jk2(jj) = 1. / (math.pi * ak) * math.fusedmuladd(p3(ak2), math.pow(ak2,2), c[6])
    end
    for jj = 21, math.min(m, 55) do
        var ak = math.pi * (jj+1. - .25)
        var ak2 = math.pow(1. / ak, 2)
        Jk2(jj) = 1. / (math.pi * ak) * math.fusedmuladd(p2(ak2), math.pow(ak2,2), c[6])
    end
    for jj = 55, math.min(m, 279) do
        var ak = math.pi * (jj+1. - .25)
        var ak2 = math.pow(1. / ak, 2)
        Jk2(jj) = 1. / (math.pi * ak) * math.fusedmuladd(p1(ak2), math.pow(ak2,2), c[6])
    end
    return Jk2
end

return Module