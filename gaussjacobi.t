local math = require('mathfuns')
local alloc = require('alloc')
local dvector = require('dvector')
local poly = require('poly')
local bessel = require("besselroots")
local err = require("assert")

local leg = require("gausslegendre")
local cheb = require("gausschebyshev")

local size_t = uint32
local Allocator = alloc.Allocator
local dvec = dvector.DynamicVector(double)


local jacobi = terra(alloc : Allocator, n : size_t, alpha : double, beta : double)
    --check that the Jacobi parameters correspond to a nonintegrable weight function
    err.assert(n < 101 and math.min(alpha,beta) > -1.)
    --Gauss-Jacobi quadrature nodes and weights
    if alpha == 0. and beta == 0. then
        return leg.legendre(&alloc, n)
    elseif alpha == -0.5 and beta == -0.5 then
        return cheb.chebyshev_t(&alloc, n)
    elseif alpha == 0.5 and beta == 0.5 then
        return cheb.chebyshev_u(&alloc, n)
    elseif alpha == -0.5 and beta == 0.5 then
        return cheb.chebyshev_v(&alloc, n)
    elseif alpha == 0.5 and beta == -0.5 then
        return cheb.chebyshev_w(&alloc, n)
    --elseif n == 1 then
    --    return  dvec.from(&alloc, (beta - alpha) / (alpha + beta + 2.)), 
    --            dvec.from(&alloc, math.pow(2.0, alpha + beta + 1.) * math.beta(alpha + 1., beta + 1.))
    elseif n < 101 and math.max(alpha,beta) < 5. then
        return jacobi_rec(&alloc, n, alpha, beta)
    end
end

local terra jacobi_rec(alloc : Allocator, n : size_t, alpha : double, beta : double)
    --Compute nodes and weights using recurrrence relation.
    var x11, x12 = half_rec(&alloc, n, alpha, beta, 1)
    var x21, x22 = half_rec(&alloc, n, beta, alpha, 0)
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
    var c = math.pow(2.0, alpha+beta+1.) * math.gamma(2.+beta) / (math.gamma(2.+alpha+beta)*(alpha+1.)*(beta+1.))
    w:scal(c / sum_w)
    return x, w
end

local terra half_rec(alloc : Allocator, n : size_t, alpha : double, beta : double, flag : bool)
    --half_rec Jacobi polynomial recurrence relation.
    --Asymptotic formula - only valid for positive x.
    var m = (flag == 1) and math.ceil(n / 2.) or math.floor(n / 2.)
    var c1 = 1. / (2. * n + alpha + beta + 1.)
    var a1 = 1./4. - alpha*alpha
    var b1 = 1./4. - beta*beta
    var c12 = c1* c1
    var x = dvec.new(&alloc, m)
    for i = 1, m do
        var C = mmath.fusedmuladd(2., r[i], alpha - 1./2.) * (math.pi * c1)
        var C_2 = C / 2.
        x(i) = math.cos(math.fusedmuladd(c12, math.fusedmuladd(-b1, math.tan(C_2), a1 * math.cot(C_2)), C))
    end
    var P1, P2 = dvec.new(&alloc, m), dvec.new(&alloc, m)
    --loop until convergence:
    var count = 0
    repeat
        innerjacobi_rec(n, &x, alpha, beta, &P1, &P2)
        var dx2 = 0.0
        for i = 1, m do
            var dx = P1(i) / P2(i)
            var _dx2 = math.abs2(dx)
            var dx2 = terralib.select(_dx2 > dx2, _dx2, dx2)
            x(i) = x(i) - dx
        end
        count = count + 1
    until (dx2 < 1e-20) or (count==10)
    --once more for derivatives:
    innerjacobi_rec!(n, &x, alpha, beta, &P1, &P2)
    return x, P2
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
            var k0 = math.fusedmuladd(2., K, alpha + beta)
            var k1 = k0 + 1.
            var k2 = k0 + 2.
            var A = 2. * (K + 1.) * (K + (α + β + 1.)) * k0
            var B = k1 * (alpha * alpha - beta * beta)
            var C = k0 * k1 * k2
            var D = 2. * (K + alpha) * (K + beta) * k2
            var c1 = math.fusedmuladd(C, xj, B)
            Pm1, Pj = Pj, math.fusedmuladd(-D, Pm1, c1 * Pj) / A
            PPm1, PPj = PPj, math.fusedmuladd(c1, PPj, math.fusedmuladd(-D, PPm1, C * Pm1)) / A
        end
        P(j) = Pj
        PP(j) = PPj
    end 
end

local terra weights_constant(n : size_t, alpha : double, beta : double)
    --compute the constant for weights:
    var M = math.min(20, n - 1)
    var C = 1.0
    var p = -alpha * beta / n
    var m = 1
    repeat
        C = C + p
        p = p * (-(m + alpha) * (m + beta) / (m + 1.) / (n - m))
        abs(p / C) < eps(Float64) / 100 && break
    until (math.abs(p/C) < 1e-17) or (m==M)
    return math.pow(2.0, alpha + beta + 1) * C
end


local terra jacobi_asy(n : size_t, alpha : double, beta : double)
    --ASY  Compute nodes and weights using asymptotic formulae.
    --Determine switch between interior and boundary regions:
    var nbdy = 10
    var bdyidx1 = n - (nbdy - 1):n
    var bdyidx2 = nbdy:-1:1

    --Interior formula:
    x, w = asy1(n, alpha, beta, nbdy)

    --Boundary formula (right):
    var xbdy, wbdy = asy2(n, alpha, beta, nbdy)
    for i = 0
        x(i), w(i) = xbdy(i), wbdy(i)
    end

    --Boundary formula (left):
    if alpha ~= beta then
        xbdy = asy2(n, beta, alpha, nbdy)
    end
    x[bdyidx2] = -xbdy[1]
    w[bdyidx2] = xbdy[2]
    w:scal(weights_constant(n, alpha, beta))
    return x, w
end




local terra asy1(n : size_t, alpha : double, beta : double, nbdy : size_t)
    --Algorithm for computing nodes and weights in the interior.
    --Approximate roots via asymptotic formula: (Gatteschi and Pittaluga, 1985)
    var K = π*(2(n:-1:1).+α.-0.5)/(2n+α+β+1)
    tt = K .+ (1/(2n+α+β+1)^2).*((0.25-α^2).*cot.(K/2).-(0.25-β^2).*tan.(K/2))

    --First half (x > 0):
    t = tt[tt .≤ π/2]
    mint = t[end-nbdy+1]
    idx = 1:max(findfirst(t .< mint)-1, 1)

    --Newton iteration
    for _ in 1:10
        var vals, ders = feval_asy1(n, α, β, t, idx)  --Evaluate
        dt = vals./ders
        t += dt  --Next iterate
        if norm(dt[idx],Inf) < sqrt(eps(Float64))/100
            break
        end
    end
    vals, ders = feval_asy1(n, α, β, t, idx)  # Once more for luck
    t = t + vals./ders

    --Store
    x_right = cos.(t)
    w_right = 1 ./ ders.^2

    --Second half (x < 0):
    α, β = β, α
    t = π .- tt[1:(n-length(x_right))]
    mint = t[nbdy]
    idx = max(findfirst(t .> mint), 1):length(t)

    --Newton iteration
    for _ in 1:10
        vals, ders = feval_asy1(n, α, β, t, idx)  --evaluate.
        dt = vals./ders  # Newton update.
        t = t + dt
        if norm(dt[idx],Inf) < sqrt(eps(Float64))/100
            break
        end
    end
    vals, ders = feval_asy1(n, α, β, t, idx)  # Once more for luck.
    t += vals./ders  # Newton update.

    --Store
    x_left = cos.(t)
    w_left = 1 ./ ders.^2

    return vcat(-x_left, x_right), vcat(w_left, w_right)
end


function feval_asy1(n::Integer, α::Float64, β::Float64, t::AbstractVector, idx)
    --Number of terms in the expansion:
    M = 20

    --Number of elements in t:
    N = length(t)

    --The sine and cosine terms:
    A = repeat((2n+α+β).+(1:M),1,N).*repeat(t',M)/2 .- (α+1/2)*π/2  # M × N matrix
    cosA = cos.(A)
    sinA = sin.(A)

    sinT = repeat(sin.(t)',M)
    cosT = repeat(cos.(t)',M)
    cosA2 = cosA.*cosT .+ sinA.*sinT
    sinA2 = sinA.*cosT .- cosA.*sinT

    sinT = hcat(ones(N), cumprod(repeat((csc.(t/2)/2),1,M-1), dims=2))  # M × N matrix
    secT = sec.(t/2)/2

    _vec = [(α+j-1/2)*(-α+j-1/2)/(2n+α+β+j+1)/j for j in 1:M-1]
    P1 = [1;cumprod(_vec)]
    P1[3:4:end] = -P1[3:4:end]
    P1[4:4:end] = -P1[4:4:end]
    P2 = Matrix(1.0I, M, M)
    for l in 1:M
        _vec = [(β+j-1/2)*(-β+j-1/2)/(2n+α+β+j+l)/j for j in 1:M-l-2]
        P2[l,l+1:M-2] = cumprod(_vec)
    end
    PHI = repeat(P1,1,M).*P2

    _vec = [(α+j-1/2)*(-α+j-1/2)/(2n+α+β+j-1)/j for j in 1:M-1]
    P1 = [1;cumprod(_vec)]
    P1[3:4:end] = -P1[3:4:end]
    P1[4:4:end] = -P1[4:4:end]
    P2 = Matrix(1.0I, M, M)
    for l in 1:M
        _vec = [(β+j-1/2)*(-β+j-1/2)/(2n+α+β+j+l-2)/j for j in 1:M-l-2]
        P2[l,l+1:M-2] = cumprod(_vec)
    end
    PHI2 = repeat(P1,1,M).*P2

    S = zeros(N)
    S2 = zeros(N)
    for m in 1:M
        l = 1:2:m
        phi = PHI[l, m]
        dS1 = (sinT[:, l]*phi) .* cosA[m, :]
        phi2 = PHI2[l, m]
        dS12 = (sinT[:, l]*phi2) .* cosA2[m, :]
        l = 2:2:m
        phi = PHI[l, m]
        dS2 = (sinT[:, l]*phi) .* sinA[m, :]
        phi2 = PHI2[l, m]
        dS22 = (sinT[:, l]*phi2) .* sinA2[m, :]
        if m - 1 > 10 && norm(dS1[idx] + dS2[idx], Inf) < eps(Float64) / 100
            break
        end
        S .+= dS1
        S .+= dS2
        S2 .+= dS12
        S2 .+= dS22
        sinT[:,1:m] .*= secT
    end

    --Constant out the front:
    dsa = α^2/2n
    dsb = β^2/2n
    dsab = (α+β)^2/4n
    ds = dsa + dsb - dsab
    s = ds
    i = 1
    dsold = ds # to fix α = -β bug.
    while abs(ds/s)+dsold > eps(Float64)/10
        dsold = abs(ds/s)
        i += 1
        tmp = -(i-1)/(i+1)/n
        dsa = tmp*dsa*α
        dsb = tmp*dsb*β
        dsab = tmp*dsab*(α+β)/2
        ds = dsa + dsb - dsab
        s = s + ds
    end
    p2 = exp(s)*sqrt(2π*(n+α)*(n+β)/(2n+α+β))/(2n+α+β+1)
    # g is a vector of coefficients in
    # ``\Gamma(z) = \frac{z^{z-1/2}}{\exp(z)}\sqrt{2\pi} \left(\sum_{i} B_i z^{-i}\right)``, where B_{i-1} = g[i].
    # https://math.stackexchange.com/questions/1714423/what-is-the-pattern-of-the-stirling-series
    g = [1, 1/12, 1/288, -139/51840, -571/2488320, 163879/209018880,
         5246819/75246796800, -534703531/902961561600,
         -4483131259/86684309913600, 432261921612371/514904800886784000]
    f(z) = dot(g, [1;cumprod(ones(9)./z)])

    # Float constant C, C2
    C = 2*p2*(f(n+α)*f(n+β)/f(2n+α+β))/π
    C2 = C*(α+β+2n)*(α+β+1+2n)/(4*(α+n)*(β+n))

    vals = C*S

    # Use relation for derivative:
    ders = (n*((α-β).-(2n+α+β)*cos.(t)).*vals .+ (2*(n+α)*(n+β)*C2).*S2)./(2n+α+β)./sin.(t)
    denom = 1 ./ (sin.(abs.(t)/2).^(α+0.5).*cos.(t/2).^(β+0.5))
    vals .*= denom
    ders .*= denom

    return vals, ders
end