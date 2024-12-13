-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local tmath = require('mathfuns')
local alloc = require('alloc')
local stack = require('stack')
local svector = require('svector')
local dvector = require('dvector')
local poly = require('poly')
local err = require("assert")
local range = require("range")

local size_t = uint32
local Allocator = alloc.Allocator
local dvec = dvector.DynamicVector(double)
local dstack = stack.DynamicStack(double)

--table that holds the main implementations of quadrature rules
local imp = {}
--table containing api overloaded functions calling underlying implementation
local gauss = {}

--base clas for quadrature rules
local function QuadruleBase(rule, x_type, w_type)
    --add entry types
    rule.entries:insert({field = "_0", type = x_type})
    rule.entries:insert({field = "_1", type = w_type})
    rule:setconvertible("tuple")
    --entry lookup quadrature points and weights
    rule.metamethods.__entrymissing = macro(function(entryname, self)
        if entryname=="x" then
            return `self._0
        end
        if entryname=="w" then
            return `self._1
        end
    end)
end

--affine scaling of quadrature rule
local terra affinescaling(x : &dvec, w : &dvec, a : double, b : double, alpha : double, beta : double)
    var sb, sa, s, exp = b / 2., a / 2., (b-a) / 2.0, alpha+beta+1.0
    for i = 0, x:size() do
        x(i) = (x(i) + 1) * sb + (1 - x(i)) * sa
        w(i) = w(i) * tmath.pow(s, exp)
    end
end

local terra isodd(n : int)
    return n % 2 == 1
end

local terra iseven(n : int)
    return n % 2 == 0
end

local svec8d = svector.StaticVector(double, 8)

local airy_roots_8 = terralib.constant(terralib.new(double[8], {
--the first 8 roots of the Airy function in Float64 precision
--https://mathworld.wolfram.com/AiryFunctionZeros.html
    -2.338107410459767,
    -4.08794944413097,
    -5.520559828095551,
    -6.786708090071759,
    -7.944133587120853,
    -9.022650853340981,
    -10.04017434155809,
    -11.00852430373326}
))

--approximation of airy roots
local terra airyroots(t : double)
    return tmath.pow(t, 2. / 3.) * 
        (1.0  +  5./48. * tmath.pow(t, -2)  -  5./36. * tmath.pow(t, -4)  +  
            (77125./82944.) * tmath.pow(t, -6)  -  108056875. / 6967296. * tmath.pow(t, -8)  +  
                162375596875. / 334430208. * tmath.pow(t, -10))
end

local terra hermite_xinit(r : double, nu : double, a : double)
    return tmath.sqrt(
        tmath.abs( nu + tmath.pow(2., 2./3.) * r * tmath.pow(nu, 1./3.) + 
        (1./5. * tmath.pow(2., 4./3.)) * tmath.pow(r, 2) * tmath.pow(nu,-1./3.) + 
        (11./35. - tmath.pow(a, 2) -12./175.) * tmath.pow(r, 3) / nu + 
        ((16./1575.) * r + (92./7875.) * tmath.pow(r, 4)) * tmath.pow(2.,2./3.) * tmath.pow(nu,-5./3.) -
        ((15152./3031875.) * tmath.pow(r, 5) + (1088/121275) * tmath.pow(r, 2)) * tmath.pow(2, 1./3) * tmath.pow(nu, -7./3.)
    ))
end

local terra tricomi(k : int, m : int, nu : double)
    return tmath.pi * ((4*m + 3) - 4*k) / nu
end

local terra tricomiroots(k : int, m : int, nu : double)
    var res = tricomi(k, m, nu) --roots of this function are approximated
    var t = 0.5 * tmath.pi
    escape
        for i = 0, 7 do --experimentally verified
            emit quote 
                --var x = t - tmath.sin(t) - res
                --var dx = 1. - tmath.cos(t)
                --t = t - x / dx
                t = t - (t - tmath.sin(t) - res) / (1. - tmath.cos(t))
            end
        end
    end
    return t
end

local terra hermite_xinit_sin(r : double, nu : double, a : double)
    var t = tmath.pow( tmath.cos(0.5 * r), 2)
    var lambda = nu * t - ( (t + 0.25) / tmath.pow(t-1., 2) + (3.*tmath.pow(a,2) - 1.) ) / (3*nu)
    return tmath.sqrt(lambda)
end

local unitrange_i = range.Unitrange(int, "infinite")
local steprange_i = range.Steprange(int)

local terra hermite_initialguess(alloc : Allocator, n : size_t)
    --HERMITEINTITIALGUESSES(N), Initial guesses for Hermite zeros.
    --
    --[1] L. Gatteschi, Asymptotics and bounds for the zeros of Laguerre
    --polynomials: a survey, J. Comput. Appl. Math., 144 (2002), pp. 7-27.
    --
    --[2] F. G. Tricomi, Sugli zeri delle funzioni di cui si conosce una
    --rappresentazione asintotica, Ann. Mat. Pura Appl. 26 (1947), pp. 283-300.

    --Error if n < 20 because initial guesses are based on asymptotic expansions:
    --err.assert(n >= 20)

    --Gatteschi formula involving airy roots [1].
    --These initial guess are good near x = sqrt(n+1/2);
    var a : double
    var m : int
    if isodd(n) then
        --bess = (1:m)*π
        m = (n-1) >> 1
        a = .5
    else
        --bess = ((0:m-1) .+ 0.5)*π
        m = n >> 1
        a = -.5
    end
    var nu = 4. * m + 2. * a + 2.

    --combine 8 first precomputed values and thereafter approximations
    -- of the airy roots
    var r1 = svec8d{airy_roots_8} >> range.transform(hermite_xinit, {nu=nu, a=a})
    var r2 = unitrange_i.new(9) >> 
                range.transform([terra(i : int) return -airyroots(3*tmath.pi / 8. * (4*i - 1.)) end]) >> 
                    range.transform(hermite_xinit, {nu=nu, a=a})
    var airyrts = range.join(r1, r2)

    --Tricomi initial guesses. Equation (2.1) in [1]. Originally in [2].
    --These initial guesses are good near x = 0.
    var tricrts = steprange_i.new(m, 0, -1) >> 
                    range.transform(tricomiroots, {m=m, nu = nu}) >>
                        range.transform(hermite_xinit_sin, {nu=nu,a=a})

    --patch together
    var p = [int](tmath.floor(0.5 * m))
    var xinit = range.join(
        airyrts >> range.take(p),
        tricrts >> range.drop(p)
    )
        
    --fill dynamic stack
    var x = dstack.new(alloc, n)
    xinit:pushall(&x)

    --add zero element for odd order case
    if isodd(n) then
        x:push(0.0)
    end
    -- return as a dvector
    return [dvec](x:__move())
end

local terra hermpoly_rec(x0 : double, n : size_t)
    --evaluation of scaled Hermite poly using recurrence
    var w = tmath.exp(-tmath.pow(x0,2) / (4*n))
    var wc = 0
    var Hold = 1.0
    var H = x0
    for k = 1, n do
        Hold, H = H, x0 * H / tmath.sqrt(k+1.) - Hold / tmath.sqrt(1. + 1./k)
        while tmath.abs(H) >= 100 and wc < n do
            --regularise
            H    = H * w
            Hold = Hold * w
            wc = wc + 1
        end
        k = k + 1
    end
    for k = wc+1, n+1 do
        H = H * w
        Hold = Hold * w
    end
    return H, -x0 * H + tmath.sqrt(double(n)) * Hold
end

local terra apply_hermpoly_rec(x : double, n : size_t)
    --Compute single Hermite nodes and weights using recurrence relation.
    var sqrtoftwo = tmath.sqrt(double(2))
    x = x * sqrtoftwo
    --newton-rahpson iteration
    var f, df = 0.0, 0.0
    escape 
        for k = 1, 10 do
            emit quote 
                f, df = hermpoly_rec(x, n)
                x = x - f / df
            end
        end
    end
    x = x / sqrtoftwo               --quadrature point
    var w = 1.0 / tmath.pow(df, 2)  --quadrature weights
    return x, w
end

local terra hermite_rec(alloc : Allocator, n : size_t)
    --compute initial guess
    var x = hermite_initialguess(alloc, n)
    --range yielding points and weights
    var quadrule = x >> range.transform(apply_hermpoly_rec, {n = n})
    --allocate space for weights
    var w = dvec.new(alloc, n)
    for i,q in range.enumerate(quadrule) do
        x:set(i, q._0)
        w:set(i, q._1)
    end
    --use symmetry to establish complete rule
    x.size = n --ToDo: we used x as a view here. Fix when views are ready.
    --use symmetry to get the other Legendre nodes and weights:
    var m = terralib.select(isodd(n), (n+1) >> 1, n >> 1)
    var alpha = tmath.sqrt(tmath.pi)
    for i = 0, m do
        var xx = x(i)
        x(i) = -xx
        x(n - 1 - i) = xx
        w(i) = w(i) * tmath.exp(-tmath.pow(xx, 2)) * alpha
        w(n - 1 - i) = w(i)
    end
    return x, w
end

terra imp.unweightedgausshermite(alloc : Allocator, n : size_t)
    --compute the gauss-hermite nodes and weights in O(n) time.
    if n == 1 then
        --special case n==1
        var x = dvec.all(alloc, 1, 0.0)
        var w = dvec.all(alloc, 1, tmath.sqrt(tmath.pi))
        return x, w
    elseif n <= 100 then
       --Newton's method with three-term recurrence
       var x, w = hermite_rec(&alloc, n)
       return x, w
    end
end

local besselj0_roots = terralib.constant(terralib.new(double[20],{
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
}))

local besselj1_on_besselj0_roots = terralib.constant(terralib.new(double[10],{
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
}))

local poly1 = poly.Polynomial(double, 2)
local poly2 = poly.Polynomial(double, 3)
local poly3 = poly.Polynomial(double, 4)
local poly4 = poly.Polynomial(double, 5)
local poly5 = poly.Polynomial(double, 6)
local poly6 = poly.Polynomial(double, 7)

terra bessel_zero_roots(alloc : Allocator, m : size_t)
    --bessel0roots roots of besselj(0,x). Use asymptotics.
    --Use McMahon's expansion for the remainder (NIST, 10.21.19):
    var jk = dvec.new(alloc, m)
    var c = arrayof(double, 1071187749376. / 315., 0.0, -401743168. / 105., 0.0, 120928. / 15., 0.0, -124. / 3., 0.0, 1.0, 0.0)
    var p2 = poly2.from(1.0, c[6], c[4])
    var p3 = poly3.from(1.0, c[6], c[4], c[2])
    --First 20 are precomputed:
    for jj = 0, tmath.min(m, 20) do
        jk(jj) = besselj0_roots[jj]
    end
    for jj = 20, tmath.min(m, 47) do
        var ak = tmath.pi * (jj+1. - .25)
        var ak82 = tmath.pow(.125 / ak, 2)
        jk(jj) = ak + .125 / ak * p3(ak82)
    end
    for jj = 47, tmath.min(m, 344) do
        var ak = tmath.pi * (jj+1. - .25)
        var ak82 = tmath.pow(.125 / ak, 2)
        jk(jj) = ak + .125 / ak * p2(ak82)
    end    
    return jk
end

terra besselJ1(alloc : Allocator, m : size_t)
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
    for jj = 0, tmath.min(m, 10) do
        Jk2(jj) = besselj1_on_besselj0_roots[jj]
    end
    for jj = 10, tmath.min(m, 15) do
        var ak = tmath.pi * (jj+1. - .25)
        var ak2 = tmath.pow(1. / ak, 2)
        Jk2(jj) = 1. / (tmath.pi * ak) * tmath.fusedmuladd(p4(ak2), tmath.pow(ak2,2), c[6])
    end
    for jj = 15, tmath.min(m, 21) do
        var ak = tmath.pi * (jj+1. - .25)
        var ak2 = tmath.pow(1. / ak, 2)
        Jk2(jj) = 1. / (tmath.pi * ak) * tmath.fusedmuladd(p3(ak2), tmath.pow(ak2,2), c[6])
    end
    for jj = 21, tmath.min(m, 55) do
        var ak = tmath.pi * (jj+1. - .25)
        var ak2 = tmath.pow(1. / ak, 2)
        Jk2(jj) = 1. / (tmath.pi * ak) * tmath.fusedmuladd(p2(ak2), tmath.pow(ak2,2), c[6])
    end
    for jj = 55, tmath.min(m, 279) do
        var ak = tmath.pi * (jj+1. - .25)
        var ak2 = tmath.pow(1. / ak, 2)
        Jk2(jj) = 1. / (tmath.pi * ak) * tmath.fusedmuladd(p1(ak2), tmath.pow(ak2,2), c[6])
    end
    return Jk2
end

local terra legpts_nodes(alloc : Allocator, n : size_t, a : dvec)
    --asymptotic expansion for the Gauss-Legendre nodes
    var vn = 1. / (n + 0.5)
    var m = a:size()
    var nodes = dvec.new(&alloc, n)
    a:map(&nodes, tmath.cot)
    var vn2 = vn * vn
    var vn4 = vn2 * vn2
    var p = poly2.from(2595. / 15360., 6350. / 15360., 3779. / 15360.)
    if n <= 255 then
        var vn6 = vn4 * vn2
        for i = 0, m do
            var u = nodes(i)
            var u2 = u * u
            var ai = a:get(i)
            var ai2 = ai * ai
            var ai3 = ai2 * ai
            var ai5 = ai2 * ai3
            var node = ai + (u - 1. / ai) / 8. * vn2
            var v1 = (6. * (1. + u2) / ai + 25. / ai3 - u * tmath.fusedmuladd(31., u2, 33.)) / 384.
            var v2 = u * p(u2)
            var v3 = (1. + u2) * (-tmath.fusedmuladd(31. / 1024., u2, 11. / 1024.) / ai + u / 512. / ai2 + -25. / 3072. / ai3)
            var v4 = (v2 - 1073. / 5120. / ai5 + v3)
            node = tmath.fusedmuladd(v1, vn4, node)
            node = tmath.fusedmuladd(v4, vn6, node)
            nodes(i) = node
        end
    end
    --compose with 'cos'
    for i=0,m do
        nodes(i) = -tmath.cos(nodes(i))
        nodes(n-1-i) = -nodes(i)
    end
    if (n % 2 ~= 0) then nodes(m-1) = 0.0 end
    return nodes
end

local terra legpts_weights(alloc : Allocator, n : size_t, a : dvec)
    --asymptotic expansion for the Gauss-Legendre weights
    var m = a:size()
    var vn = 1. / (n + 0.5)
    var vn2 = vn * vn
    var weights = dvec.new(&alloc, n)
    a:map(&weights, tmath.cot)
    var p2 = poly2.from(-27.0, -84.0, -56.0)
    var p3 = poly3.from(153. / 1024., 295. / 256., 187. / 96., 151. / 160.)
    var q2 = poly2.from(-65. / 1024., -119. / 768., -35. / 384.)
    var r2 = poly2.from(5. / 512., 15. / 512., 7. / 384.)
    if n <= 170 then
        for i = 0, m do
            var u = weights(i)
            var u2 = u * u
            var ai = a(i)
            var air1 = 1. / ai
            var ai2 = ai * ai
            var air2 = 1. / ai2
            var ua = u * ai
            var W1 = tmath.fusedmuladd(ua-1., air2, 1.0) / 8.
            var W2 = poly2.from(
                p2(u2), 
                tmath.fusedmuladd(-3.0, tmath.fusedmuladd(u2, -2.0, 1.0), 6. * ua), 
                tmath.fusedmuladd(ua, -31.0, 81.0)
            )
            var W3 = poly6.from(
                p3(u2), 
                q2(u2) * u, 
                r2(u2), 
                tmath.fusedmuladd(u2, 1. / 512., -13. / 1536.) * u, 
                tmath.fusedmuladd(u2, -7. / 384., 53. / 3072.), 
                3749. / 15360. * u, 
                -1125. / 1024.
            )
            var W = poly2.from(1. / vn2 + W1, W2(air2) / 384., W3(air1))
            weights(i) = W(vn2)
        end
    end
    var bJ1 = besselJ1(&alloc, m)
    --use symmetry to get the other half:
    for i = 0, m do
        var v = a(i)
        weights(i) = 2. / (bJ1(i) * (v / tmath.sin(v)) * weights(i))
        weights(n - 1 - i) = weights(i)
    end
    return weights
end

local terra asy(alloc : Allocator, n : size_t)
    --compute Gauss-Legendre nodes and weights using asymptotic expansions. Complexity O(n).
    --Nodes and weights:
    var m = (n + 1) >> 1
    var a = bessel_zero_roots(&alloc, m)
    a:scal(1. / (n + 0.5))
    var x = legpts_nodes(&alloc, n, a)
    var w = legpts_weights(&alloc, n, a)
    return x, w
end

local terra innerRec(x : &dvec, myPm1 : &dvec, myPPm1 : &dvec)
    --Evaluate Legendre and its derivative using three-term recurrence relation.
    var n = x:size()
    var m = myPm1:size()
    for j = 0, m do
        var xj = x(j)
        var Pm2 = 1.0
        var Pm1 = xj
        var PPm1 = 1.0
        var PPm2 = 0.0
        for k = 1, n do
            var K : double = k
            Pm2, Pm1 = Pm1, tmath.fusedmuladd((2. * K + 1.) * Pm1, xj, - K * Pm2) / (K + 1.)
            PPm2, PPm1 = PPm1, ((2. * K + 1.) * tmath.fusedmuladd(xj, PPm1, Pm2) - K * PPm2) / (K + 1.)
        end
        myPm1(j) = Pm1
        myPPm1(j) = PPm1
    end
end

local terra rec(alloc : Allocator, n : size_t)
    --compute Gauss-Legendre nodes and weights using Newton's method
    --three-term recurrence is used for evaluation. Complexity O(n^2).
    --initial guesses:
    var m = (n + 1) >> 1
    var x, w = asy(&alloc, n)
    --allocate vectors for Newton corrections
    var PP1, PP2 = dvec.new(&alloc, m), dvec.new(&alloc, m)
    --perform Newton to find zeros of Legendre polynomial:
    for iter = 0, 3 do
        innerRec(&x, &PP1, &PP2)
        for i = 0, m do 
            x(i) = x(i) - PP1(i) / PP2(i)
        end
    end
    --use symmetry to get the other Legendre nodes and weights:
    for i = 0, m do
        x(n - 1 - i) = -x(i)
        w(i) = PP2(i)
        w(n - 1 - i) = -w(i)
    end
    if (n % 2 ~= 0) then x(m-1) = 0.0 end
    for i = 0, n do
        w(i) = 2. / ((1. - x(i)*x(i)) * w(i)*w(i))
    end
    return x, w
end

terra imp.legendre(alloc : Allocator, n : size_t)
    err.assert(n < 101)
    if n==1 then
        return dvec.from(&alloc, 0.0), dvec.from(&alloc, 2.0)
    elseif n==2 then
        return dvec.from(&alloc, -1.0 / tmath.sqrt(3.0), 1.0 / tmath.sqrt(3.0)), 
            dvec.from(&alloc, 1.0, 1.0)
    elseif n==3 then
        return dvec.from(&alloc, -tmath.sqrt(3.0 / 5.0), 0.0, tmath.sqrt(3.0 / 5.0)), 
            dvec.from(&alloc, 5.0 / 9.0, 8.0 / 9.0, 5.0 / 9.0)
    elseif n==4 then
        var a = 2.0 / 7.0 * tmath.sqrt(6.0 / 5.0)
        return dvec.from(&alloc, -tmath.sqrt(3. / 7. + a), -tmath.sqrt(3./7.-a), tmath.sqrt(3./7.-a), tmath.sqrt(3./7.+a)),
            dvec.from(&alloc, (18. - tmath.sqrt(30.)) / 36., (18. + tmath.sqrt(30.)) / 36., (18. + tmath.sqrt(30.)) / 36., (18. - tmath.sqrt(30.)) / 36.)
    elseif n==5 then
        var b = 2.0 * tmath.sqrt(10.0 / 7.0)
        return dvec.from(&alloc, -tmath.sqrt(5. + b) / 3., -tmath.sqrt(5. - b) / 3., 0.0, tmath.sqrt(5. - b) / 3., tmath.sqrt(5. + b) / 3.),
            dvec.from(&alloc, (322. - 13. * tmath.sqrt(70.)) / 900., (322. + 13. * tmath.sqrt(70.)) / 900., 128. / 225., (322. + 13. * tmath.sqrt(70.)) / 900., (322. - 13. * tmath.sqrt(70.)) / 900.)
    elseif n <= 60 then
        --Newton's method with three-term recurrence
        var x, w = rec(&alloc, n)
        return x, w
    else
        --use asymptotic expansions:
        var x, w = asy(&alloc, n)
        return x, w
    end
end

terra imp.chebyshev_t(alloc : Allocator, n : size_t)
    var x, w = dvec.new(&alloc, n), dvec.new(&alloc, n)
    for i = 0, n do
        var k = n - i
        x(i) = tmath.cos((2. * k - 1.) * tmath.pi / (2. * n))
        w(i) = tmath.pi / n
    end
    return x, w
end

terra imp.chebyshev_u(alloc : Allocator, n : size_t)
    var x, w = dvec.new(&alloc, n), dvec.new(&alloc, n)
    for i = 0, n do
        var k = n - i
        x(i) = tmath.cos(k * tmath.pi / (n + 1.))
        w(i) = tmath.pi / (n + 1.) * tmath.pow(tmath.sin(k / (n + 1.) * tmath.pi), 2)
    end
    return x, w
end

terra imp.chebyshev_v(alloc : Allocator, n : size_t)
    var x, w = dvec.new(&alloc, n), dvec.new(&alloc, n)
    for i = 0, n do
        var k = n - i
        x(i) = tmath.cos((k - .5) * tmath.pi / (n + .5))
        w(i) = 2*tmath.pi / (n + .5) * tmath.pow(tmath.cos((k - .5) * tmath.pi / (2 * (n + .5))), 2)
    end
    return x, w
end

terra imp.chebyshev_w(alloc : Allocator, n : size_t)
    var x, w = dvec.new(&alloc, n), dvec.new(&alloc, n)
    for i = 0, n do
        var k = n - i
        x(i) = tmath.cos(k * tmath.pi / (n + .5))
        w(i) = 2*tmath.pi / (n + .5) * tmath.pow(tmath.sin(k * tmath.pi / (2. * (n + .5))), 2)
    end
    return x, w
end

local terra innerjacobi_rec(n : size_t, x : &dvec, alpha : double, beta : double, P : &dvec, PP : &dvec)
    --Evaluate Jacobi polyniomials and its derivative using three-term recurrence.
    var N = x:size()
    for j = 0, N do
        var xj = x(j)
        var Pj = (alpha - beta + (alpha + beta + 2.) * xj) / 2.
        var Pm1 = 1.0
        var PPj = (alpha + beta + 2.) / 2.
        var PPm1 = 0.0
        for k = 1, n do
            var K : double = k
            var k0 = tmath.fusedmuladd(2., K, alpha + beta)
            var k1 = k0 + 1.
            var k2 = k0 + 2.
            var A = 2. * (K + 1.) * (K + (alpha + beta + 1.)) * k0
            var B = k1 * (alpha * alpha - beta * beta)
            var C = k0 * k1 * k2
            var D = 2. * (K + alpha) * (K + beta) * k2
            var c1 = tmath.fusedmuladd(C, xj, B)
            Pm1, Pj = Pj, tmath.fusedmuladd(-D, Pm1, c1 * Pj) / A
            PPm1, PPj = PPj, tmath.fusedmuladd(c1, PPj, tmath.fusedmuladd(-D, PPm1, C * Pm1)) / A
        end
        P(j) = Pj
        PP(j) = PPj
    end 
end

local steprange_d = range.Steprange(double)

local terra half_rec(alloc : Allocator, n : size_t, alpha : double, beta : double, flag : bool)
    --half_rec Jacobi polynomial recurrence relation.
    --Asymptotic formula - only valid for positive x.
    var r : steprange_d
    if flag then
        r = steprange_d.new(tmath.ceil(n / 2.), 1, -1, range.include_last) 
    else
        r = steprange_d.new(tmath.floor(n / 2.), 1, -1, range.include_last)
    end
    var m = r:size()
    var c1 = 1. / (2. * n + alpha + beta + 1.)
    var a1 = 0.25 - alpha*alpha
    var b1 = 0.25 - beta*beta
    var c12 = c1* c1
    var x = dvec.new(&alloc, m)
    for i = 0, m do
        var C = tmath.fusedmuladd(2., r(i), alpha - 0.5) * (tmath.pi * c1)
        var C_2 = C / 2.
        x(i) = tmath.cos(tmath.fusedmuladd(c12, tmath.fusedmuladd(-b1, tmath.tan(C_2), a1 * tmath.cot(C_2)), C))
    end
    --loop until convergence:
    var P1, P2 = dvec.new(&alloc, m), dvec.new(&alloc, m)
    var count = 0
    repeat
        innerjacobi_rec(n, &x, alpha, beta, &P1, &P2)
        var dx2 = 0.0
        for i = 0, m do
            var dx = P1(i) / P2(i)
            var _dx2 = dx * dx
            dx2 = terralib.select(_dx2 > dx2, _dx2, dx2)
            x(i) = x(i) - dx
        end
        count = count + 1
    until (dx2 < 1e-22) or (count==20)
    --twice more for derivatives:
    innerjacobi_rec(n, &x, alpha, beta, &P1, &P2)
    return x, P2
end

local terra jacobi_rec(alloc : Allocator, n : size_t, alpha : double, beta : double)
    --Compute nodes and weights using recurrrence relation.
    var x11, x12 = half_rec(&alloc, n, alpha, beta, true)
    var x21, x22 = half_rec(&alloc, n, beta, alpha, false)
    --allocate vectors for nodes and weights
    var x, w = dvec.new(&alloc, n), dvec.new(&alloc, n)
    var m1, m2 = x11:size(), x21:size()
    var sum_w = 0.0
    for i = 0, m2 do
        var idx = m2 - 1 - i
        var xi = -x21(i)
        var der = x22(i)
        var wi = 1. / ((1. - xi*xi) * der*der)
        w(idx) = wi
        x(idx) = xi
        sum_w = sum_w + wi
    end
    for i = 0, m1 do
        var idx = m2 + i
        var xi = x11(i)
        var der = x12(i)
        var wi = 1. / ((1. - xi * xi) * der * der)
        w(idx) = wi
        x(idx) = xi
        sum_w = sum_w + wi
    end
    var c = tmath.pow(2.0, alpha+beta+1.) * tmath.gamma(2.+alpha) * tmath.gamma(2.+beta) / (tmath.gamma(2.+alpha+beta)*(alpha+1.)*(beta+1.))
    w:scal(c / sum_w)
    return x, w
end

terra imp.jacobi_main(alloc : Allocator, n : size_t, alpha : double, beta : double)
    --check that the Jacobi parameters correspond to a nonintegrable weight function
    err.assert(n < 101 and tmath.min(alpha,beta) > -1 and tmath.max(alpha,beta) <= 5)
    --Gauss-Jacobi quadrature nodes and weights
    if alpha == 0. and beta == 0. then
        return imp.legendre(&alloc, n)
    elseif alpha == -0.5 and beta == -0.5 then
        return imp.chebyshev_t(&alloc, n)
    elseif alpha == 0.5 and beta == 0.5 then
        return imp.chebyshev_u(&alloc, n)
    elseif alpha == -0.5 and beta == 0.5 then
        return imp.chebyshev_v(&alloc, n)
    elseif alpha == 0.5 and beta == -0.5 then
        return imp.chebyshev_w(&alloc, n)
    elseif n==1 then
        var x, w = dvec.new(&alloc, 1), dvec.new(&alloc, 1) 
        x(0) = (beta - alpha) / (alpha + beta + 2.)
        w(0) = tmath.pow(2, alpha + beta + 1.) * tmath.beta(alpha + 1., beta + 1.)
        return x, w
    elseif n < 101 and tmath.max(alpha,beta) <= 5. then
        return jacobi_rec(&alloc, n, alpha, beta)
    end
end

terra imp.jacobi_main_test(alloc : Allocator, n : size_t, alpha : double, beta : double)
    --check that the Jacobi parameters correspond to a nonintegrable weight function
    err.assert(n < 101 and tmath.min(alpha,beta) > -1 and tmath.max(alpha,beta) <= 5)
    if n==1 then
        var x, w = dvec.new(&alloc, 1), dvec.new(&alloc, 1) 
        x(0) = (beta - alpha) / (alpha + beta + 2.)
        w(0) = tmath.pow(2, alpha + beta + 1.) * tmath.beta(alpha + 1., beta + 1.)
        return x, w
    elseif n < 101 and tmath.max(alpha,beta) <= 5. then
        return jacobi_rec(&alloc, n, alpha, beta)
    end
end

for _,method in ipairs{"legendre_t", "chebyshev_w_t", "chebyshev_u_t", "chebyshev_v_t", "chebyshev_t_t", "jacobi_t", "hermite_t"} do
    gauss[method] = terralib.types.newstruct(method)
    QuadruleBase(gauss[method], dvec, dvec)
end

gauss.legendre = terralib.overloadedfunction("legendre",
{
    terra(alloc : Allocator, n : size_t)
        var qr : gauss.legendre_t = imp.legendre(alloc, n)
        return qr
    end,
    terra(alloc : Allocator, n : size_t, I : tuple(double,double))
        var qr : gauss.legendre_t = imp.legendre(alloc, n)
        affinescaling(&qr.x, &qr.w, I._0, I._1, 0.0, 0.0)
        return qr
    end
})

gauss.chebyshev_w = terralib.overloadedfunction("chebyshev_w",
{
    terra(alloc : Allocator, n : size_t)
        var qr : gauss.chebyshev_w_t = imp.chebyshev_w(alloc, n)
        return qr
    end,
    terra(alloc : Allocator, n : size_t, I : tuple(double,double))
        var qr : gauss.chebyshev_w_t = imp.chebyshev_w(alloc, n)
        affinescaling(&qr.x, &qr.w, I._0, I._1, 0.5, -0.5)
        return qr
    end
})

gauss.chebyshev_u = terralib.overloadedfunction("chebyshev_u",
{
    terra(alloc : Allocator, n : size_t)
        var qr : gauss.chebyshev_u_t = imp.chebyshev_u(alloc, n)
        return qr
    end,
    terra(alloc : Allocator, n : size_t, I : tuple(double,double))
        var qr : gauss.chebyshev_u_t = imp.chebyshev_u(alloc, n)
        affinescaling(&qr.x, &qr.w, I._0, I._1, 0.5, 0.5)
        return qr
    end
})

gauss.chebyshev_v = terralib.overloadedfunction("chebyshev_v",
{
    terra(alloc : Allocator, n : size_t)
        var qr : gauss.chebyshev_v_t = imp.chebyshev_v(alloc, n)
        return qr
    end,
    terra(alloc : Allocator, n : size_t, I : tuple(double,double))
        var qr : gauss.chebyshev_v_t = imp.chebyshev_v(alloc, n)
        affinescaling(&qr.x, &qr.w, I._0, I._1, -0.5, 0.5)
        return qr
    end
})

gauss.chebyshev_t = terralib.overloadedfunction("chebyshev_t",
{
    terra(alloc : Allocator, n : size_t)
        var qr : gauss.chebyshev_t_t = imp.chebyshev_t(alloc, n)
        return qr
    end,
    terra(alloc : Allocator, n : size_t, I : tuple(double,double))
        var qr : gauss.chebyshev_t_t = imp.chebyshev_t(alloc, n)
        affinescaling(&qr.x, &qr.w, I._0, I._1, -0.5, -0.5)
        return qr
    end
})

--conditional selection of the algorithms based on wheter
--we run the testsuite
local function runalltests()
    return _G["runalltests"]
end
imp.jacobi = pcall(runalltests) and imp.jacobi_main_test or imp.jacobi_main
    
gauss.jacobi = terralib.overloadedfunction("jacobi",
{
    terra(alloc : Allocator, n : size_t, alpha: double, beta : double)
        var qr : gauss.jacobi_t = imp.jacobi(alloc, n, alpha, beta)
        return qr
    end,
    terra(alloc : Allocator, n : size_t, alpha: double, beta : double, I : tuple(double,double))
        var qr : gauss.jacobi_t = imp.jacobi(alloc, n, alpha, beta)
        affinescaling(&qr.x, &qr.w, I._0, I._1, alpha, beta)
        return qr
    end
})

--affine scaling of quadrature rule
local terra hermitescaling(x : &dvec, w : &dvec, o : double, s : double)
    for i = 0, x:size() do
        x(i) = (x(i) - o) / s
        w(i) = w(i) * s 
    end
end

local struct hermiteaffinetrans{
    origin : double
    scaling : double
}

hermiteaffinetrans.metamethods.__cast = function(from, to, exp)
    if to == hermiteaffinetrans then
        return quote
            var v = exp
        in
            hermiteaffinetrans{v.origin, v.scaling}
        end
    end
    error("ArgumentError: not a valid cast.")
end

gauss.hermite = terralib.overloadedfunction("hermite", {
    terra(alloc : Allocator, n : size_t)
        var qr : gauss.hermite_t = imp.unweightedgausshermite(alloc, n)
        return qr
    end,
    terra(alloc : Allocator, n : size_t, I : hermiteaffinetrans)
        var qr : gauss.hermite_t = imp.unweightedgausshermite(alloc, n)
        hermitescaling(&qr.x, &qr.w, I.origin, I.scaling)
        return qr
    end
})

local function getunderlyingtype(t)
    if not terralib.types.istype(t) then
        if t.tree then
            t = t:gettype()
        elseif t.type then
            t = t.type
        end
    end
    if t:ispointer() then
        return t.type
    else
        return t
    end
end

local productrule = macro(function(...)
    local args = terralib.newlist{...}
    local D = #args
    local xargs, wargs = terralib.newlist(), terralib.newlist()
    for k,v in pairs(args) do
        local tp = getunderlyingtype(v)
        local x, w = getunderlyingtype(tp.entries[1]), getunderlyingtype(tp.entries[2])
        assert(x.isrange and w.isrange)
    end
    for i,qr in ipairs(args) do
        xargs:insert(quote in &qr.x end)
        wargs:insert(quote in &qr.w end)
    end
    --quadrule type
    local quadrule = terralib.types.newstruct("tensorquadrule")
    --return quadrature rule
    return quote
        var x = range.product([xargs])
        var w = range.product([wargs]) >> range.reduce(range.op.mul)
        escape
            QuadruleBase(quadrule, x.type, w.type)
        end
    in
        quadrule{x, w}
    end
end)

--add additional methods
gauss.QuadruleBase = QuadruleBase
gauss.productrule = productrule

return gauss
