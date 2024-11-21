import "terraform"

local alloc = require("alloc")
local base = require("base")
local concept = require("concept-new")
local vecbase = require("vector")
local svector = require("svector")
local dvector = require("dvector")
local dmatrix = require("dmatrix")
local tmath = require("mathfuns")
local dual = require("dual")
local range = require("range")
local gauss = require("gauss")
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

local dualDouble = dual.DualNumber(double)

local VDIM = 3

local dvecDouble = dvector.DynamicVector(double)
local struct quad(base.AbstractBase) {
    w: dvecDouble
    x: dvecDouble
    n: int64
}

local Alloc = alloc.Allocator
terra quad.staticmethods.new_hermite(alloc: Alloc, n: int64)
    var t = gsl.gsl_integration_fixed_hermite
    var work = gsl.gsl_integration_fixed_alloc(t, n, 0, 0.5, 0.0, 0.0)
    defer gsl.gsl_integration_fixed_free(work)
    var w = gsl.gsl_integration_fixed_weights(work)
    var x = gsl.gsl_integration_fixed_nodes(work)
    var q: quad
    q.w = dvecDouble.new(alloc, n)
    q.x = dvecDouble.new(alloc, n)
    q.n = n
    for i = 0, n do
        q.w(i) = w[i] / tmath.sqrt(2.0 * math.pi)
        q.x(i) = x[i]
    end
    return q
end

terra quad.staticmethods.new_legendre(alloc: Alloc, n: int64)
    var x, w = gauss.legendre(alloc, n)
    var q: quad
    q.w = dvecDouble.new(alloc, n)
    q.x = dvecDouble.new(alloc, n)
    q.n = n
    for i = 0, n do
        q.w(i) = w:get(i)
        q.x(i) = x:get(i)
    end
    return q    
end

local pow
terraform pow(n: I, x: T) where {I: concept.Integral, T: concept.Real}
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

local Vector = vecbase.Vector
local vbasis
terraform vbasis(p: &int32, v: &T) where {T: concept.Number}
    var res = [v.type.type](1)
    for i = 0, VDIM do
        res = res * pow(p[i], v[i])
    end
    return res
end

local struct tensor_quad(base.AbstractBase) {
    x: dvecDouble,
    w: dvecDouble,
    n: int64
}

tensor_quad.staticmethods.from = terra(alloc: Alloc, q1: &quad, q2: &quad, q3: &quad)
    var n = q1.n * q2.n * q3.n
    var q: tensor_quad
    q.n = n
    q.w = dvecDouble.new(alloc, n)
    q.x = dvecDouble.new(alloc, 3 * n)
    var idx = 0
    for i1 = 0, q1.n do
        for i2 = 0, q2.n do
            for i3 = 0, q3.n do
                q.w(idx) = q1.w(i1) * q2.w(i2) * q3.w(i3)
                q.x(3 * idx + 0) = q1.x(i1)
                q.x(3 * idx + 1) = q2.x(i2)
                q.x(3 * idx + 2) = q3.x(i3)
                idx = idx + 1
            end
        end
    end
    return q
end

local local_maxwellian
terraform local_maxwellian(q: &tensor_quad, nv: I, p: &int32, coeff: &V)
    where {I: concept.Integral, V: Vector}
    var m1: coeff.type.type.eltype = 0
    var m2 = [svector.StaticVector(m1.type, VDIM)].zeros()
    var m3: m1.type = 0

    for k = 0, q.n do
        var v = &q.x(VDIM * k)
        var bv = [m1.type](0)
        for i = 0, nv do
            var alpha = p + VDIM * i
            bv = bv + coeff(i) * vbasis(alpha, v)
        end
        var w = q.w(k)
        m1 = m1 + w * bv
        for j = 0, VDIM do
            m2(j) = m2(j) + w * v[j] * bv 
        end
        var vsqr = [w.type](0)
        for j = 0, VDIM do
            vsqr = vsqr + v[j] * v[j]
        end
        m3 = m3 + w * vsqr * bv
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

local Real = concept.Real
terraform halfspace(
    ntestv: int64, test_powers: &int32, rho: T1, u: &V1, theta: T2, normal: &V2
)
    where {T1: Real, V1: Vector, T2: Real, V2: Vector}
    var un = u:dot(normal)
end

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
local dVec = dvector.DynamicVector(double)
local iMat = dmatrix.DynamicMatrix(int32)
local dualDouble = dual.DualNumber(double)
local ddVec = dvector.DynamicVector(dualDouble)
local io = terralib.includec("stdio.h")
terra main()
    var alloc: DefaultAlloc
    var n = 21
    var qh = quad.new_hermite(&alloc, n)
    var qm = tensor_quad.from(&alloc, &qh, &qh, &qh)
    var p = iMat.from(&alloc, {
        {2, 0, 1},
        {0, 2, 0},
        {1, 0, 2},
    })
    var coeff = ddVec.zeros(&alloc, p:rows())
    for i = 0, coeff:size() do
        coeff(i).val = 1
        coeff(i).tng = 1
    end
    var rho, u, theta = local_maxwellian(&qm, p:rows(), &p(0, 0), &coeff)
    io.printf("rho %g %g\n", rho.val, rho.tng)
    for i = 0, VDIM do
        io.printf("u(%d) %g %g\n", i, u(i).val, u(i).tng)
    end
    io.printf("theta %g %g\n", theta.val, theta.tng)
end
main()
