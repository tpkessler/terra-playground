-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"

local alloc = require("alloc")
local base = require("base")
local concepts = require("concepts")
local vecbase = require("vector")
local svector = require("svector")
local dvector = require("dvector")
local dmatrix = require("dmatrix")
local tmath = require("mathfuns")
local dual = require("dual")
local range = require("range")
local gauss = require("gauss")
local halfhermite = require("halfrangehermite")
local lambda = require("lambda")
local tmath = require("mathfuns")
local stack = require("stack")
local qr = require("qr")
local thread = setmetatable(
    {C = terralib.includec("pthread.h")},
    {__index = function(self, key)
                   return rawget(self.C, key) or self.C["pthread_" .. key]
                end
    }
)
terralib.linklibrary("libpthread.so.0")

local gsl = terralib.includec("gsl/gsl_integration.h")
terralib.linklibrary("libgsl.so")

local VDIM = 3

local dvecDouble = dvector.DynamicVector(double)
local Alloc = alloc.Allocator
local struct hermite_t {}
gauss.QuadruleBase(hermite_t, dvecDouble, dvecDouble)
local terra hermite(alloc: Alloc, n: int64): hermite_t
    var t = gsl.gsl_integration_fixed_hermite
    var work = gsl.gsl_integration_fixed_alloc(t, n, 0, 0.5, 0.0, 0.0)
    defer gsl.gsl_integration_fixed_free(work)
    var w = gsl.gsl_integration_fixed_weights(work)
    var x = gsl.gsl_integration_fixed_nodes(work)
    var wq = dvecDouble.new(alloc, n)
    var xq = dvecDouble.new(alloc, n)
    for i = 0, n do
        wq(i) = w[i] / tmath.sqrt(2.0 * math.pi)
        xq(i) = x[i]
    end
    return xq, wq
end

local pow
terraform pow(n: I, x: T) where {I: concepts.Integral, T: concepts.Real}
    escape
        local pow_raw = terralib.memoize(function(I, T)
            local terra impl(n: I, x: T): T
                if n == 0 then
                    return [T](1)
                end
                if n == 1 then
                    return x
                end
                var p2 = impl(n / 2, x * x)
                return terralib.select(n % 2 == 0, p2, x * p2)
            end
            return impl
        end)
        emit quote return [pow_raw(n.type, x.type)](n, x) end
    end
end

local monomial
terraform monomial(v: &T, p: &I) where {I: concepts.Integral, T: concepts.Number}
    var res = [v.type.type](1)
    for i = 0, VDIM do
        res = res * pow(p[i], v[i])
    end
    return res
end

local iMat = dmatrix.DynamicMatrix(int32)
local struct MonomialBasis(base.AbstractBase){
    p: iMat
}

MonomialBasis.staticmethods.new = terra(p: iMat)
    var basis: MonomialBasis
    basis.p = p
    return basis
end

do
    -- HACK Define our own lambda as a more flexible solution
    local struct Func {p: &int32}
    Func.metamethods.__apply = macro(function(self, x)
        return `monomial(x, self.p)
    end)
    local struct iterator {
        basis: &MonomialBasis
        func: Func
        idx: int64
        len: int64
    }
    terra iterator:getvalue()
        var p = &self.basis.p(self.idx, 0)
        self.func.p = p
        return self.func
    end

    terra iterator:next()
        self.idx = self.idx + 1
    end

    terra iterator:isvalid()
        return self.idx < self.len
    end

    terra MonomialBasis:getiterator()
        var func: Func
        return iterator {self, func, 0, self.p:rows()}
    end
    MonomialBasis.iterator = iterator
    range.Base(MonomialBasis, iterator, Func)
end


local l2inner
terraform l2inner(f, g, q)
    var it = q:getiterator()
    var xw = it:getvalue()
    var x, w = xw
    var res = [w.type](0)
    for xw in q do
        var x, w = xw
        var arg = [&w.type](&x)
        res = res + w * f(arg) * g(arg)
    end
    return res
end

local Vector = vecbase.Vector
local local_maxwellian
terraform local_maxwellian(basis, coeff: &V, quad)
    where {I: concepts.Integral, V: Vector}
    var m1: coeff.type.type.eltype = 0
    var m2 = [svector.StaticVector(m1.type, VDIM)].zeros()
    var m3: m1.type = 0

    var it = quad:getiterator()
    var xw = it:getvalue()
    var x, w = xw
    for bc in range.zip(basis, coeff) do
        var cnst = lambda.new([terra(v: &w.type) return 1.0 end])
        m1 = m1 + l2inner(bc._0, cnst, quad) * bc._1
        escape
            for i = 0, VDIM - 1 do
                local vi = `lambda.new([terra(v: &w.type) return v[i] end])
                emit quote
                    m2(i) = m2(i) + l2inner(bc._0, [vi], quad) * bc._1
                end
            end
        end
        var vsqr = lambda.new([
                        terra(v: &w.type)
                            var vsqr = [v.type.type](0)
                            escape
                                for j = 0, VDIM - 1 do
                                    emit quote vsqr = vsqr + v[j] * v[j] end
                                end
                            end
                            return vsqr
                        end
                    ])        
        m3 = m3 + l2inner(bc._0, vsqr, quad) * bc._1
    end

    var rho = m1
    var u = [m2.type].zeros()
    for j = 0, VDIM do
        u(j) = m2(j) / rho
    end
    var theta = m3 / rho
    for j = 0, VDIM do
        theta = theta - u(j) * u(j)
    end
    theta = theta / VDIM
    return rho, u, theta
end

local RecDiff = concepts.newconcept("RecDiff")
RecDiff.traits.ninit = concepts.traittag
RecDiff.traits.depth = concepts.traittag
RecDiff.traits.eltype = concepts.traittag
local Stack = concepts.Stack
RecDiff.methods.getcoeff = {&RecDiff, concepts.Integral, &Stack} -> {}
RecDiff.methods.getinit = {&RecDiff, &Stack} -> {}

local Integer = concepts.Integer
local olver
local io = terralib.includec("stdio.h")
terraform olver(alloc, rec: &R, yn: &V)
    where {R: RecDiff, S: Stack, V: Vector}
    var y0 = [svector.StaticVector(R.traits.eltype, R.traits.ninit)].zeros()
    var nmax = yn:size()
    var n0 = y0:size()
    var dim: int64 = nmax - n0
    var sys = [dmatrix.DynamicMatrix(R.traits.eltype)].zeros(alloc, dim, dim)
    var rhs = [dvector.DynamicVector(R.traits.eltype)].zeros(alloc, dim)
    var hrf = [dvector.DynamicVector(R.traits.eltype)].zeros(alloc, dim)
    var y = [svector.StaticVector(R.traits.eltype, R.traits.depth + 1)].zeros()
    for i = 0, dim do
        var n = n0 + i
        rec:getcoeff(n, &y)
        for offset = 0, [R.traits.depth] do
            var j = i + offset - [R.traits.depth] / 2
            if j >= 0 and j < dim then
                sys(i, j) = y:get(offset)
            end
        end
        rhs:set(i, y:get([R.traits.depth]))
    end
    rec:getinit(&y0)
    for i = 0, n0 do
        rec:getcoeff(n0 + i, &y)
        var r = rhs:get(i)
        for j = i, n0 do
            r = r - y:get(j - i) * y0:get(j)
        end
        rhs:set(i, r)
    end
    var qr = [qr.QRFactory(sys.type, rhs.type)].new(&sys, &hrf)
    qr:factorize()
    qr:solve(false, &rhs)
    for i = 0, n0 do
        yn:set(i, y0:get(i))
    end
    for i = n0, nmax do
        yn:set(i, rhs:get(i - n0))
    end
end

local struct Interval(concepts.Base){
    left: concepts.Number
    right: concepts.Number
}
Interval.traits.eltype = concepts.traittag

local clenshawcurtis
terraform clenshawcurtis(alloc, n: N, rec: &R, dom: &I)
    where {N: concepts.Integral, R: RecDiff, S: Stack, I: Interval}
    var x = [dvector.DynamicVector(I.traits.eltype)].new(alloc, n)
    ([range.Unitrange(int)].new(0, n)
        >> range.transform(
            [terra(i: int, n: int)
                return tmath.cos(tmath.pi * (2 * i + 1) / (2 * n))
            end],
            {n = n})
    ):collect(&x)

    var nmax = 20
    if n > 10 then
        nmax = 2 * n
    end
    var mom = [dvector.DynamicVector(R.traits.eltype)].zeros(alloc, nmax)
    olver(alloc, rec, &mom)

    var w = [dvector.DynamicVector(R.traits.eltype)].zeros(alloc, n)
    (mom >> range.take(n)):collect(&w)
    var sys = [dmatrix.DynamicMatrix(R.traits.eltype)].zeros(alloc, n, n)
    for j = 0, n do
        sys(0, j) = 1
        sys(1, j) = x(j)
    end
    for i = 2, n do
        for j = 0, n do
            sys(i, j) = 2 * x(j) * sys(i - 1, j) - sys(i - 2, j)
        end
    end
    var hrf = [dvector.DynamicVector(R.traits.eltype)].zeros(alloc, n)
    var qr = [qr.QRFactory(sys.type, w.type)].new(&sys, &hrf)
    qr:factorize()
    qr:solve(false, &w)

    var xq = [dvector.DynamicVector(I.traits.eltype)].new(alloc, n)
    (x >> range.transform([
            terra(
                x: I.traits.eltype,
                a: I.traits.eltype,
                b: I.traits.eltype
                )
                return (b + a) / 2 + (b - a) / 2 * x
            end],
            {a = dom.left, b = dom.right})
    ):collect(&xq)

    var wq = [dvector.DynamicVector(I.traits.eltype)].new(alloc, n)
    (w >> range.transform([
            terra(
                w: I.traits.eltype,
                a: I.traits.eltype,
                b: I.traits.eltype
                )
                return (b - a) / 2 * w
            end],
            {a = dom.left, b = dom.right})
    ):collect(&wq)

    return xq, wq
end

local function IntervalFactory(T)
    local struct impl{
        left: T
        right: T
    }
    impl.metamethods.__tostring = function(self)
        return ("Interval(%s)"):format(tostring(T))
    end
    base.AbstractBase(impl)
    impl.traits.eltype = T
    impl.staticmethods.new = terra(left: T, right: T)
        return impl {left, right}
    end
    return impl
end

local ExpMom = terralib.memoize(function(T)
    local struct impl(base.AbstractBase) {
        a: T
    }
    function impl.metamethods.__tostring(self)
        return ("ExpMom(%s)"):format(tostring(T))
    end
    base.AbstractBase(impl)
    impl.traits.depth = 5
    impl.traits.ninit = 2
    impl.traits.eltype = T
    terraform impl:getcoeff(n: I, y: &S) where {I: concepts.Integral, S: Stack}
        var a = self.a
        y:set(0, -a * (n + 1))
        y:set(1, -2 * a * (n + 1))
        y:set(2, -2 * (a + n * n - 1))
        y:set(3, 2 * a * (n - 1))
        y:set(4, a * (n - 1))
        y:set(5, 2 * (tmath.exp(-4 * a) + terralib.select(n % 2 == 0, 1, -1)))
    end
    terraform impl:getinit(y: &S) where {S: Stack}
        var a = self.a
        var arg = 2 * tmath.sqrt(a)
        var y0 = tmath.sqrt(tmath.pi) * tmath.erf(arg) / arg 
        var y1 = -y0 - (tmath.exp(-4 * a) - 1) / (2 * a)
        y:set(0, y0)
        y:set(1, y1)
    end
    impl.staticmethods.new = terra(a: T)
        return impl {a}
    end
    return impl
end)

local HalfSpaceQuadrature = terralib.memoize(function(T)
    local SVec = svector.StaticVector(T, VDIM)
    local struct impl {
        normal: SVec
    }
    impl.metamethods.__tostring = function(self)
        return ("HalfSpaceQuadrature(T)"):format(tostring(T))
    end
    base.AbstractBase(impl)

    local new
    terraform new(narg ...)
        var n: SVec
        escape
            for i = 0, VDIM - 1 do
                emit quote n(i) = narg.["_" .. i] end
            end
        end
        return impl {n}
    end

    terraform new(narg: &T) where {T: concepts.Any}
        var n: SVec
        for i = 0, VDIM do
            n(i) = narg[i]
        end
        return impl {n} 
    end

    terraform new(narg: SVec)
        return impl {narg}
    end

    impl.staticmethods.new = new

    local reverse
    terraform reverse(w: &V) where {V: Vector}
        for i = 0, w:size() / 2 do
            var j = w:size() - 1 - i
            var tmp = w(i)
            w(i) = w(j)
            w(j) = tmp
        end
    end

    local ExpMomT = ExpMom(T)
    local IntT = IntervalFactory(T)
    local VecT = dvector.DynamicVector(T)

    local castvector
    terraform castvector(dest: &V1, src: &V2) where {V1: Vector, V2: Vector}
        (
            @src >> range.transform([
                terra(x: V2.eltype)
                    return [V1.eltype](x)
                end
            ])
        ):collect(dest)
    end

    local normalize
    terraform normalize(v: &V) where {V: Vector}
        var nrmsqr = v:dot(v) + 1e-15
        v:scal(1 / tmath.sqrt(nrmsqr))
    end

    local householder
    terraform householder(v: &V1, h: &V2) where {V1: Vector, V2: Vector}
        var dot = v:dot(h)
        for i = 0, v:size() do
            v(i) = v(i) - 2 * dot * h(i)
        end
    end

    local io = terralib.includec("stdio.h")
    terraform impl:maxwellian(alloc, n: N, rho: T, u: &S, theta: T)
        where {N: concepts.Integral, S: Stack}
        --[=[
            We compute at quadrature rule for the integration weight
                [(v, normal) > 0] M[rho, u, theta](v),
            for v in R^3. Here, normal is the normal of the half space
            spanned by all vectors with positive inner product with the normal.
            M[rho, u, theta] denotes the Maxwellian with density rho, bulk
            velocity u and temperature theta. After an affine change of variables,
            the weight reads
                [(v, normal) > -(u, normal) / sqrt(theta)] rho M[1, 0, 1](v)
            so that we can focus our efforts on the reference Maxwellian with
            unit density and temperature and zero bulk velocity.
            However, u and theta now enter in the definition of the shifted
            half space. First, we split the normal component into
            the finite interval (-(u, normal), 0) and the finite interval
            (0, infty). Then, we construct a quadrature rule for the finite
            interval, followed by the finite interval. Lastly, we tensorize
            the 1D rule with Hermite rules for the unbounded tangential
            components. The quadrature rule for the finite interval is computed
            via moment fitting in the Chebyshev basis after a change of coordinates
            to the reference interval (-1, 1). In this context, moment-fitted
            quadratures are known as Clenshaw-Curtis rules.
        --]=]
        -- Compute the limit of integration for the finite domain
        var un = self.normal:dot(u)
        -- This number is not the real Mach number but misses ratio of specific
        -- heats.
        var mach = un / tmath.sqrt(theta)
        var dom = IntT.new(-mach, 0)
        -- Moments in the Chebyshev basis are computed via recursion as a naive
        -- evaluation of the integrals leads to rapid loss of precision even
        -- for modest polynomial degree. ExpMomT contains the recursion for
        -- moments of the the function exp(-scal (x + 1)^2) on the interval (-1, 1).
        -- Hence, we first have to map our unit Maxwellian from (-mach, 0)
        -- to (-1, 1). This results in the following scaling factor
        var scal = tmath.pow(mach / 2, 2) / 2
        var rec = ExpMomT.new(scal)
        var qfinite = clenshawcurtis(alloc, n, &rec, &dom)
        var xfinite = VecT.new(alloc, n)
        var wfinite = VecT.new(alloc, n)
        castvector(&xfinite, &qfinite._0)
        castvector(&wfinite, &qfinite._1)
        -- The recursion is defined for the Maxwellian centered around the left
        -- boundary but in our application it is centered around the right boundary.
        -- We fix this by simply reverting weights, knowing that the Chebyshev
        -- points are always symmetricly distributed on the interval.
        reverse(&wfinite)
        -- Include the normalization constant of the reference Maxwellian.
        wfinite:scal(rho / tmath.sqrt(2 * tmath.pi))

        -- Construct the quadrature rule for the infinite domain (0, infty)
        var nhalf = n / 2 + 1
        var qhalf = halfhermite.halfrangehermite(alloc, nhalf)
        var xhalf = VecT.new(alloc, nhalf)
        var whalf = VecT.new(alloc, nhalf)
        castvector(&xhalf, &qhalf._0)
        castvector(&whalf, &qhalf._1)
        whalf:scal(rho)

        var xnormal = range.join(xfinite, xhalf)
        var wnormal = range.join(wfinite, whalf)

        var qhermite = hermite(alloc, nhalf)
        var xhermite = VecT.new(alloc, nhalf)
        var whermite = VecT.new(alloc, nhalf)
        castvector(&xhermite, &qhermite._0)
        castvector(&whermite, &qhermite._1)

        var diff = SVec.new()
        escape
            for i = 0, VDIM - 1 do
                emit quote
                    var ni = self.normal(i)
                    diff(i) = terralib.select(i == 0, ni - 1, ni)
                end
            end
        end
        normalize(&diff)
        var points = range.product(xnormal, xhermite, xhermite)
                     >> range.transform([
                        terra(
                            x1: T,
                            x2: T,
                            x3: T,
                            u: &S,
                            theta: T,
                            diff: SVec
                        )
                            var x = SVec.from(x1, x2, x3)
                            householder(&x, &diff)
                            var y: x.type
                            escape
                                for i = 0, VDIM - 1 do
                                    emit quote
                                        y(i) = tmath.sqrt(theta) * x(i) + u(i)
                                    end
                                end
                            end
                            return y(0), y(1), y(2)
                        end
                    ], {u = u, theta = theta, diff = diff})

        var weights = range.product(wnormal, whermite, whermite)
                      >> range.reduce(range.op.mul)

        return points, weights
    end

    return impl
end)

local terra outflow(
    num_threads: int64,
    -- Dimension of test space and the result arrays
    ntestx: int64,
    ntextv: int64,
    -- Result of half space integral
    resval: &double,
    restng: &double,
    -- Dimension of trial space and the input arrays
    ntrialx: int64,
    ntrialv: int64,
    -- Evaluation point
    val: &double,
    -- Direction of derivative
    tng: &double,
    -- Number of spatial quadrature points
    nqx: int64,
    -- Spatial dimension
    ndim: int64,
    -- Sampled normals
    normal: &double,
    -- Point evaluation of spatial test functions at quadrature points
    testdata: &double,
    testrow: &int32,
    testcolptr: &int32,
    -- Point evaluation of spatial trial functions at quadrature points
    trialdata: &double,
    trialcol: &int32,
    trialrowptr: &int32,
    -- Monomial powers of polynomial approximation in velocity
    test_powers: &int32,
    trial_powers: &int32
)
end

local DefaultAlloc = alloc.DefaultAllocator()
local dualDouble = dual.DualNumber(double)
local ddVec = dvector.DynamicVector(dualDouble)
local ddStack = stack.DynamicStack(dualDouble)
local HalfSpaceDual = HalfSpaceQuadrature(dualDouble)
local lib = terralib.includec("stdlib.h")
terra main(argc: int, argv: &rawstring)
    var alloc: DefaultAlloc
    var n = 5
    if argc > 1 then
        n = lib.strtol(argv[1], nil, 10)
    end
    io.printf("Number of quadrature points is %d\n", n)
    var qh = hermite(&alloc, n)
    var rule = gauss.productrule(&qh, &qh, &qh)
    var quad = range.zip(&rule.x, &rule.w)
    var p = iMat.from(&alloc, {
        {3, 0, 0},
        {0, 2, 0},
        {0, 0, 2},
    })
    var basis = MonomialBasis.new(p)
    var coeff = ddVec.zeros(&alloc, p:rows())
    for i = 0, coeff:size() do
        coeff(i).val = 1.0 / 3.0
        coeff(i).tng = i
    end
    var rho, u, theta = local_maxwellian(&basis, &coeff, &quad)
    return 0
end
-- main(0, nil)
-- terralib.saveobj("boltzmann.o", {main = main})

return {
    HalfSpaceQuadrature = HalfSpaceQuadrature,
}
