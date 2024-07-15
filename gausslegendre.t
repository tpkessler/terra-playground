local math = require('mathfuns')
local alloc = require('alloc')
local dvector = require('dvector')
local poly = require('poly')
local bessel = require("besselroots")
local err = require("assert")

local io = terralib.includec("stdio.h")

local size_t = uint32
local Allocator = alloc.Allocator
local dvec = dvector.DynamicVector(double)

local poly2 = poly.Polynomial(double, 3)

local terra legpts_nodes(alloc : Allocator, n : size_t, a : dvec)
    --asymptotic expansion for the Gauss-Legendre nodes
    var vn = 1. / (n + 0.5)
    var m = a:size()
    var nodes = dvec.new(&alloc, n)
    a:map(&nodes, math.cot)
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
            var v1 = (6. * (1. + u2) / ai + 25. / ai3 - u * math.fusedmuladd(31., u2, 33.)) / 384.
            var v2 = u * p(u2)
            var v3 = (1. + u2) * (-math.fusedmuladd(31. / 1024., u2, 11. / 1024.) / ai + u / 512. / ai2 + -25. / 3072. / ai3)
            var v4 = (v2 - 1073. / 5120. / ai5 + v3)
            node = math.fusedmuladd(v1, vn4, node)
            node = math.fusedmuladd(v4, vn6, node)
            nodes(i) = node
        end
    end
    --compose with 'cos'
    for i=0,m do
        nodes(i) = -math.cos(nodes(i))
        nodes(n-1-i) = -nodes(i)
    end
    if (n % 2 ~= 0) then nodes(m-1) = 0.0 end
    return nodes
end

local poly3 = poly.Polynomial(double, 4)
local poly6 = poly.Polynomial(double, 7)

local terra legpts_weights(alloc : Allocator, n : size_t, a : dvec)
    --asymptotic expansion for the Gauss-Legendre weights
    var m = a:size()
    var vn = 1. / (n + 0.5)
    var vn2 = vn * vn
    var weights = dvec.new(&alloc, n)
    a:map(&weights, math.cot)
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
            var W1 = math.fusedmuladd(ua-1., air2, 1.0) / 8.
            var W2 = poly2.from(
                p2(u2), 
                math.fusedmuladd(-3.0, math.fusedmuladd(u2, -2.0, 1.0), 6. * ua), 
                math.fusedmuladd(ua, -31.0, 81.0)
            )
            var W3 = poly6.from(
                p3(u2), 
                q2(u2) * u, 
                r2(u2), 
                math.fusedmuladd(u2, 1. / 512., -13. / 1536.) * u, 
                math.fusedmuladd(u2, -7. / 384., 53. / 3072.), 
                3749. / 15360. * u, 
                -1125. / 1024.
            )
            var W = poly2.from(1. / vn2 + W1, W2(air2) / 384., W3(air1))
            weights(i) = W(vn2)
        end
    end
    var bJ1 = bessel.besselJ1(&alloc, m)
    --use symmetry to get the other half:
    for i = 0, m do
        var v = a(i)
        weights(i) = 2. / (bJ1(i) * (v / math.sin(v)) * weights(i))
        weights(n - 1 - i) = weights(i)
    end
    return weights
end

local terra asy(alloc : Allocator, n : size_t)
    --compute Gauss-Legendre nodes and weights using asymptotic expansions. Complexity O(n).
    --Nodes and weights:
    var m = (n + 1) >> 1
    var a = bessel.bessel_zero_roots(&alloc, m)
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
            Pm2, Pm1 = Pm1, math.fusedmuladd((2. * K + 1.) * Pm1, xj, - K * Pm2) / (K + 1.)
            PPm2, PPm1 = PPm1, ((2. * K + 1.) * math.fusedmuladd(xj, PPm1, Pm2) - K * PPm2) / (K + 1.)
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

local legendre = terra(alloc : Allocator, n : size_t)
    err.assert(n < 101)
    if n==1 then
        return dvec.from(&alloc, 0.0), dvec.from(&alloc, 2.0)
    elseif n==2 then
        return dvec.from(&alloc, -1.0 / math.sqrt(3.0), 1.0 / math.sqrt(3.0)), 
            dvec.from(&alloc, 1.0, 1.0)
    elseif n==3 then
        return dvec.from(&alloc, -math.sqrt(3.0 / 5.0), 0.0, math.sqrt(3.0 / 5.0)), 
            dvec.from(&alloc, 5.0 / 9.0, 8.0 / 9.0, 5.0 / 9.0)
    elseif n==4 then
        var a = 2.0 / 7.0 * math.sqrt(6.0 / 5.0)
        return dvec.from(&alloc, -math.sqrt(3. / 7. + a), -math.sqrt(3./7.-a), math.sqrt(3./7.-a), math.sqrt(3./7.+a)),
            dvec.from(&alloc, (18. - math.sqrt(30.)) / 36., (18. + math.sqrt(30.)) / 36., (18. + math.sqrt(30.)) / 36., (18. - math.sqrt(30.)) / 36.)
    elseif n==5 then
        var b = 2.0 * math.sqrt(10.0 / 7.0)
        return dvec.from(&alloc, -math.sqrt(5. + b) / 3., -math.sqrt(5. - b) / 3., 0.0, math.sqrt(5. - b) / 3., math.sqrt(5. + b) / 3.),
            dvec.from(&alloc, (322. - 13. * math.sqrt(70.)) / 900., (322. + 13. * math.sqrt(70.)) / 900., 128. / 225., (322. + 13. * math.sqrt(70.)) / 900., (322. - 13. * math.sqrt(70.)) / 900.)
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

return {
    legendre = legendre
}