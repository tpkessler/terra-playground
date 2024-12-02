local tmath = require("mathfuns")
local alloc = require("alloc")
local stack = require("stack")
local svector = require("svector")
local dvector = require("dvector")
local poly = require("poly")
local err = require("assert")
local range = require("range")

local io = terralib.includec("stdio.h")

local size_t = uint32
local Allocator = alloc.Allocator
local dvec = dvector.DynamicVector(double)
local dstack = stack.DynamicStack(double)

local terra isodd(n : int)
    return n % 2 == 1
end

local terra iseven(n : int)
    return n % 2 == 0
end

local svec8d = svector.StaticVector(double, 8)

--the first 10 roots of the Airy function in Float64 precision
--https://mathworld.wolfram.com/AiryFunctionZeros.html
local airy_roots_8 = terralib.constant(terralib.new(double[8], {
    -2.338107410459767,
    -4.08794944413097,
    -5.520559828095551,
    -6.786708090071759,
    -7.944133587120853,
    -9.022650853340981,
    -10.04017434155809,
    -11.00852430373326}
    ---11.93601556323626,
    ---12.828776752865757}
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

local unitrange = range.Unitrange(int, "infinite")
local steprange = range.Steprange(int)

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
    var r2 = unitrange.new(9) >> 
                range.transform([terra(i : int) return -airyroots(3*tmath.pi / 8. * (4*i - 1.)) end]) >> 
                    range.transform(hermite_xinit, {nu=nu, a=a})
    var airyrts = range.join(r1, r2)

    --Tricomi initial guesses. Equation (2.1) in [1]. Originally in [2].
    --These initial guesses are good near x = 0.
    var tricrts = steprange.new(m, 0, -1) >> 
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

local terra unweightedgausshermite(alloc : Allocator, n : size_t)
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

local DefaultAllocator =  alloc.DefaultAllocator()

terra main()
    var alloc : DefaultAllocator
    var x, w = unweightedgausshermite(&alloc, 5)
    for i, xx in range.enumerate(x) do
        io.printf("w(%d) = %0.15f\n", i, xx)
    end
end
main()



import "terratest/terratest"
local poly = require("poly")

local DefaultAllocator =  alloc.DefaultAllocator()

testenv "" do

    terracode
        var alloc : DefaultAllocator
    end

    local N = 4

    local D = 2*N-1
    local polynomial = poly.Polynomial(double, D)

    struct exppolynomial{
        p : polynomial
    }

    exppolynomial.metamethods.__apply = terra(self : &exppolynomial, x : double)
        return self.p(x) * tmath.exp(-tmath.pow(x, 2))
    end

    local iexact = terra(N : int)
        var S = tmath.sqrt(tmath.pi)
        for n = 1, N do
            S = (2*n-1) * S / 2.0
        end
        return S
    end

    terracode 
        --create polynomial sum_{i=0}^{D} exp(-x^2) * x^i dx
        var expol = exppolynomial{}
        for k = 0, D do
            expol.p.coeffs(k) = 1.0
        end
        var S = 0.0
        for j = 0, 1 do
            S = S + iexact(j)
        end
    end

    testset "Hermite" do
        terracode
            var x, w = unweightedgausshermite(&alloc, N)
            var s = 0.0
            for t in range.zip(&x, &w) do
                var xx, ww = t
                s = s + expol(xx) * ww
            end
            io.printf("s = %0.15f\n", s)
            io.printf("S = %0.15f\n", S)
        end
        test x:size() == N and w:size() == N
        test x.data:owns_resource() and w.data:owns_resource()
        test s == S

    end
    

end
