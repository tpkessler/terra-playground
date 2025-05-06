-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
import "terratest/terratest"

local alloc = require("alloc")
local base = require("base")
local concepts = require("concepts")
local sarray = require("sarray")
local darray = require("darray")
local matrix = require("matrix")
local tmath = require("tmath")
local dual = require("dual")
local range = require("range")
local gauss = require("gauss")
local halfhermite = require("halfrangehermite")
local lambda = require("lambda")
local thread = require("thread")
local momfit = require("momfit")
local sparse = require("sparse")
local stack = require("stack")
local span = require("span")
local qr = require("qr")

local io = terralib.includec("stdio.h")

local VDIM = 3

local terraform pow(n: I, x: T) where {I: concepts.Integer, T: concepts.Real}
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

local terraform monomial(v: &T, p: &I) where {
    I: concepts.Integer, T: concepts.Number
}
    var res = [T](1)
    for i = 0, VDIM do
        res = res * pow(p[i], v[i])
    end
    return res
end

local struct background{
    rho: double
    u: sarray.StaticVector(double, VDIM)
    theta: double
}
base.AbstractBase(background)

background.staticmethods.new = (
    terra(rho: double, u: span.Span(double, VDIM), theta: double)
        var bg: background
        bg.rho = rho
        escape
            for i = 1, VDIM do
                emit quote bg.u(i - 1) = u(i - 1) end
            end
        end
        bg.theta = theta
        return bg
    end
)

local iMat = darray.DynamicMatrix(int32)
local struct MonomialBasis(base.AbstractBase){
    p: iMat
    bg: background
}

terra MonomialBasis:maxpartialdegree()
    var maxdeg = -1
    for i = 0, self.p:rows() do
        for j = 0, self.p:cols() do
            maxdeg = tmath.max(maxdeg, self.p(i, j))
        end
    end
    return maxdeg
end

local deepcopy = macro(function(A, x)
    local V = darray.DynamicVector(x:gettype().traits.eltype)
    return quote
        var p = V.new(A, x:length())
        p:copy(&x)
    in
        __move__(p)
    end
end)

local Integer = concepts.Integer
terraform MonomialBasis:quadraturerule(A, deg: I) where {I: Integer}
    var px, wx = gauss.hermite(A, deg / 2 + 1,
            {origin = 0.0, scaling = tmath.sqrt(2.)})
    wx:scal(1 / tmath.sqrt(2 * tmath.pi))
    escape
        local xarg = {}
        local warg = {}
        for i = 1, VDIM - 1 do
            xarg[i] = `deepcopy(A, px)
            warg[i] = `deepcopy(A, wx)
        end
        xarg[VDIM] = `__move__(px)
        warg[VDIM] = `__move__(wx)

        local xtpl = {}
        for i = 1, VDIM do
            xtpl[i] = symbol(double)
        end
        emit quote
            var xt = (
                range.product([xarg])
                >> range.transform([
                    terra([xtpl], bg: &background)
                        escape
                            local res = {}
                            for i = 1, VDIM do
                                res[i] = quote in
                                    tmath.sqrt(bg.theta) * [ xtpl[i] ]
                                    + bg.u(i - 1)
                                end
                            end
                            emit quote return [res] end
                        end
                    end
                ], {bg = &self.bg})
            )
            var wt = range.product([warg])
                >> range.reduce(range.op.mul)
                >> range.transform(
                    [
                        terra(w: double, bg: &background)
                            return bg.rho * w
                        end
                    ],
                    {bg = &self.bg}
                )
            return xt, wt
        end
    end
end

MonomialBasis.staticmethods.new = terra(p: iMat, bg: background)
    var basis: MonomialBasis
    basis.p = __move__(p)
    basis.bg = bg
    return basis
end

do
    -- HACK Define our own lambda as a more flexible solution
    local struct Func {
        p: &int32
        bg: &background
    }

    local Number = concepts.Number
    local terraform apply(self: Func, x: &T) where {T: Number}
        escape
            local shift = {}
            for i = 1, VDIM do
                shift[i] = quote in
                    (x[i - 1] -  self.bg.u(i - 1)) / tmath.sqrt(self.bg.theta)
                end
            end
            emit quote
                var y = arrayof(T, [shift])
                return monomial(&y[0], self.p)
            end
        end
    end

    Func.metamethods.__apply = macro(function(self, x)
        return `apply(self, x)
    end)
    
    local struct iterator {
        basis: &MonomialBasis
        func: Func
        idx: int64
        len: int64
    }
    terra iterator:getvalue()
        self.func.p = &self.basis.p(self.idx, 0)
        self.func.bg = &self.basis.bg
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
    range.Base(MonomialBasis, iterator)
end

local TensorBasis = terralib.memoize(function(T)
    local I = int32
    local iMat = darray.DynamicMatrix(I)
    local CSR = sparse.CSRMatrix(T, I)
    local Stack = stack.DynamicStack(T)
    local struct tensor_basis {
        space: CSR
        transposed: bool
        velocity: MonomialBasis
        cast: Stack
    }

    tensor_basis.metamethods.__typename = function(self)
        return ("TensorBasis(%s)"):format(tostring(T))
    end

    base.AbstractBase(tensor_basis)

    terra tensor_basis:nspacedof()
        return terralib.select(
                    self.transposed, self.space:rows(), self.space:cols()
                )
    end

    terra tensor_basis:nvelocitydof()
        return self.velocity.p:rows()
    end

    terra tensor_basis:ndof()
        return self:nspacedof() * self:nvelocitydof()
    end

    tensor_basis.staticmethods.new = (
        terra(b: CSR, transposed: bool, p: iMat, bg: background)
            var tb : tensor_basis
            tb.space = __move__(b)
            tb.transposed = transposed
            tb.velocity = MonomialBasis.new(__move__(p), bg)
            return tb
        end
    )

    local spanVDIM = span.Span(double, VDIM)
    terraform tensor_basis.staticmethods.frombuffer(
        A,
        transposed: bool,
        nq: I1,
        nx: I2,
        nnz: I3,
        data: &S,
        col: &int32,
        rowptr: &I,
        nv: I4,
        ptr: &I,
        rho: double,
        u: spanVDIM,
        theta: double)
        where {
                S: concepts.Number,
                I1: concepts.Integer,
                I2: concepts.Integer,
                I3: concepts.Integer,
                I4: concepts.Integer
              }
        var cast = Stack.new(A, nnz)
        for i = 0, nnz do
            -- Explicit cast as possibly S ~= T
            cast:push(data[i])
        end
        var tb: tensor_basis
        tb.space = CSR.frombuffer(nq, nx, nnz, &cast(0), col, rowptr)
        tb.transposed = transposed
        var bg = background.new(rho, u, theta)
        tb.velocity = MonomialBasis.new(
            __move__(iMat.frombuffer({nv, VDIM}, ptr)), bg
        )
        tb.cast = __move__(cast)

        return tb
    end

    return tensor_basis
end)

local terraform l2inner(f, g, q: &Q) where {Q}
    var it = q:getiterator()
    var x, w = it:getvalue()
    var res = [w.type](0)
    for xw in q do
        var x, w = xw
        var arg = [&w.type](&x)
        res = res + w * f(arg) * g(arg)
    end
    return res
end

local terraform l2inner(w, f, g, q: &Q) where {Q}
    var it = q:getiterator()
    var xq, wq = it:getvalue()
    var res = [wq.type](0)
    for xw in q do
        var xq, wq = xw
        var arg = [&wq.type](&xq)
        res = res + wq * w(arg) * f(arg) * g(arg)
    end
    return res
end

local terraform l2inner(w, f, g, wf: &W, xf: &X1, xg: &X2) where {W, X1, X2}
    var it = wf:getiterator()
    var wq = it:getvalue()
    var res = [wq.type](0)
    for wxy in range.zip(wf, xf, xg) do
        var wq, xq, yq = wxy
        var farg = [&wq.type](&xq)
        var garg = [&wq.type](&yq)
        res = res + wq * w(farg) * f(farg) * g(garg)
    end
    return res
end

local Vector = concepts.Vector
local Number = concepts.Number
local terraform local_maxwellian(basis : &B, coeff: &V, quad: &Q)
    where {B, V: Vector(Number), Q}
    var m1: V.traits.eltype = 0
    var m2 = [sarray.StaticVector(V.traits.eltype, VDIM)].zeros()
    var m3: V.traits.eltype = 0

    var it = quad:getiterator()
    var xref, wref = it:getvalue()
    for bc in range.zip(basis, coeff) do
        var b, c = bc
        var cnst = lambda.new([terra(v: &wref.type) return 1.0 end])
        m1 = m1 + l2inner(b, cnst, quad) * c
        escape
            for i = 0, VDIM - 1 do
                local vi = `lambda.new([terra(v: &wref.type) return v[i] end])
                emit quote
                    m2(i) = m2(i) + l2inner(b, [vi], quad) * c
                end
            end
        end
        var vsqr = lambda.new([
                        terra(v: &wref.type)
                            var vsqr = [wref.type](0)
                            escape
                                for j = 0, VDIM - 1 do
                                    emit quote vsqr = vsqr + v[j] * v[j] end
                                end
                            end
                            return vsqr
                        end
                    ])        
        m3 = m3 + l2inner(b, vsqr, quad) * c
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

testenv "Moments of local Maxwellian" do
    terracode
        var A: alloc.DefaultAllocator()
    end

    testset "Shifted Maxwellian" do
        terracode
            var p = [darray.DynamicMatrix(int32)].from(&A, {{0, 0, 0}})
            var c = [darray.DynamicVector(double)].from(&A, {1.0})
            var rho = 2.5
            var u = arrayof(double, -1, 3, -2)
            var theta = 0.75
            var bg = background.new(rho, &u[0], theta)
            var basis = MonomialBasis.new(p, bg)
            var xq, wq = basis:quadraturerule(&A, 2)
            var quad = range.zip(xq, wq)
            var locrho, locu, loctheta = local_maxwellian(&basis, &c, &quad)
        end

        test tmath.isapprox(rho, locrho, 1e-14)
        for i = 1, VDIM do
            test tmath.isapprox(u[i - 1], locu(i - 1), 1e-14)
        end
        test tmath.isapprox(theta, loctheta, 1e-14)
    end

    testset "Bumped distribution" do
        terracode
            var p = [darray.DynamicMatrix(int32)].from(&A, {{2, 0, 0}})
            var c = [darray.DynamicVector(double)].from(&A, {1.0})
            var rho = 2.5
            var u = arrayof(double, -1.5, 0, 0)
            var theta = 7.0 / 8.0
            var bg = background.new(rho, &u[0], theta)
            var basis = MonomialBasis.new(p, bg)
            var xq, wq = basis:quadraturerule(&A, 2 + 2)
            var quad = range.zip(xq, wq)
            var locrho, locu, loctheta = local_maxwellian(&basis, &c, &quad)
            var rhoref = 5.0 / 2.0
            var uref = arrayof(double, -1.5, 0.0, 0.0)
            var reftheta = 35.0 / 24.0
        end

        test tmath.isapprox(rhoref, locrho, 1e-14)
        for i = 1, VDIM do
            test tmath.isapprox(uref[i - 1], locu(i - 1), 1e-14)
        end
        test tmath.isapprox(reftheta, loctheta, 1e-14)
    end
end

local HalfSpaceQuadrature = terralib.memoize(function(T)
    local SVec = sarray.StaticVector(T, VDIM)
    local struct impl {
        normal: SVec
    }
    impl.metamethods.__typename = function(self)
        return ("HalfSpaceQuadrature(T)"):format(tostring(T))
    end
    base.AbstractBase(impl)

    local terraform new(narg ...)
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

    local terraform reverse(w: &V) where {V: Vector(concepts.Any)}
        for i = 0, w:length() / 2 do
            var j = w:length() - 1 - i
            var tmp = w(i)
            w(i) = w(j)
            w(j) = tmp
        end
    end

    local ExpMomT = momfit.ExpMom(T)
    local IntT = momfit.IntervalFactory(T)
    local VecT = darray.DynamicVector(T)

    local terraform castvector(dest: &V1, src: &V2)
        where {V1: Vector(concepts.Any), V2: Vector(concepts.Any)}
        (
            @src >> range.transform([
                terra(x: V2.traits.eltype)
                    return [V1.traits.eltype](x)
                end
            ])
        ):collect(dest)
    end

    local terraform normalize(v: &V) where {V: Vector(concepts.Real)}
        var nrmsqr = v:dot(v) + 1e-15
        v:scal(1 / tmath.sqrt(nrmsqr))
    end

    local terraform householder(v: &V1, h: &V2)
        where {V1: Vector(Number), V2: Vector(Number)}
        var dot = v:dot(h)
        for i = 0, v:length() do
            v(i) = v(i) - 2 * dot * h(i)
        end
    end

    local Integer = concepts.Integer
    local Stack = concepts.Stack
    -- HACK Unroll arguments for lambda
    local xarg = {}
    for i = 1, VDIM do
        xarg[i] = symbol(T)
    end
    terraform impl:maxwellian(A, n: N, rho: T, u: &S, theta: T)
        where {N: Integer, S: Stack(T)}
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
        -- to (-1, 1). This results in the following scaling factor:
        var scal = tmath.pow(mach / 2, 2) / 2
        var rec = ExpMomT.new(scal)
        var qfinite = momfit.clenshawcurtis(A, n, &rec, &dom)
        var xfinite = VecT.new(A, n)
        var wfinite = VecT.new(A, n)
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
        var qhalf = halfhermite.halfrangehermite(A, nhalf)
        var xhalf = VecT.new(A, nhalf)
        var whalf = VecT.new(A, nhalf)
        castvector(&xhalf, &qhalf._0)
        castvector(&whalf, &qhalf._1)
        whalf:scal(rho)

        var xnormal = range.join(__move__(xfinite), __move__(xhalf))
        var wnormal = range.join(__move__(wfinite), __move__(whalf))

        var qhermite = gauss.hermite(
            A,
            nhalf,
            {origin = 0, scaling = tmath.sqrt(2.0)}
        )
        var xhermite = VecT.new(A, nhalf)
        var whermite = VecT.new(A, nhalf)
        castvector(&xhermite, &qhermite._0)
        castvector(&whermite, &qhermite._1)
        whermite:scal(tmath.sqrt(1 / (2 * tmath.pi)))

        -- The quadrature is computed for the the reference half space
        -- defined by the normal (1, 0, 0). This configuration is mapped
        -- onto the the half space defined by the given normal with a
        -- Householder reflection, I - 2 diff diff^T, where diff is the 
        -- normalized diference between the normal n  and the reference
        -- normal e_1.
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
        var yhermite = VecT.new(A, nhalf)
        yhermite:copy(&xhermite)
        var points = range.product(
                        __move__(xnormal),
                        __move__(xhermite),
                        __move__(yhermite)
                     )
                     >> range.transform(
                            [terra(
                                [xarg],
                                u: &S,
                                theta: T,
                                diff: SVec
                            )
                                -- First rotate the quadrature points from the
                                -- reference half space to the half space defined
                                -- by the given normal ...
                                var x = SVec.from({[xarg]})
                                householder(&x, &diff)
                                var y: x.type
                                -- ... and then shift and scale with the velocity
                                -- and the temperature of the local Maxwellian.
                                escape
                                    local ret = {}
                                    for i = 0, VDIM - 1 do
                                        emit quote
                                            y(i) = (
                                                tmath.sqrt(theta) * x(i) + u(i)
                                            )
                                        end
                                        ret[i + 1] = `y(i)
                                    end
                                    emit quote return [ret] end
                                end
                            end
                        ],
                        {u = u, theta = theta, diff = diff}
                    )

        var wyhermite = VecT.new(A, nhalf)
        wyhermite:copy(&whermite)
        var weights = range.product(
                        __move__(wnormal),
                        __move__(whermite),
                        __move__(wyhermite)
                      )
                      >> range.reduce(range.op.mul)

        return points, weights
    end

    return impl
end)

local terraform maxwellian_inflow(
                    A,
                    testb: &B,
                    rho,
                    u,
                    theta,
                    normal: &N,
                    halfmom: &T)
    where {B, N, T: concepts.Number}
    var maxtestdegree = testb.velocity:maxpartialdegree()
    var loc_normal: T[VDIM]
    for k = 0, VDIM do
        -- The half space quadrature is defined on the positive half space,
        -- dot(v, n) > 0. For the boundary condition we need to compute
        -- the integral over the inflow part of the boundary, that is
        -- dot(v, n) < 0. One way to archive is to define the half space
        -- with the negative normal, -n.
        loc_normal[k] = -normal[k]
    end
    var hs = [HalfSpaceQuadrature(T)].new(&loc_normal[0])
    var xhs, whs = (
        hs:maxwellian(A, maxtestdegree + 1, rho, &u, theta)
    )
    var qhalf = range.zip(&xhs, &whs)
    var vn = lambda.new([
            terra(v: &T, normal: &T)
                var res: T = 0
                escape
                    for k = 0, VDIM - 1 do
                        emit quote res = res + v[k] * normal[k] end
                    end
                end
                return res
            end
        ],
        {normal = &loc_normal[0]})
    for i, b in range.enumerate(testb.velocity) do
        -- Because we integrate over dot(v, -n) > 0 the weight dot(v, n)
        -- has the wrong sign, so we need to correct it after quadrature.
        halfmom[i] = -l2inner(b, vn, &qhalf)
    end
end

local terraform L2Mass(testb: &B1, trialb: &B2, q: &Q, m: &M) where {
    B1, B2, Q, M
}
    for i, te in range.enumerate(testb) do
        for j, tr in range.enumerate(trialb) do
            m(i, j) = l2inner(te, tr, q)
        end
    end
end

local terraform L2Mass(weight, testb: &B1, trialb: &B2, q: &Q, m: &M) where {
    B1, B2, Q, M
}
    for i, te in range.enumerate(testb) do
        for j, tr in range.enumerate(trialb) do
            m(i, j) = l2inner(weight, te, tr, q)
        end
    end
end

local terraform MaxwellianIntegrator(A, testb: &B1, trialb: &B2, bg, m: &M) where {
    B1, B2, M
}
    var deg = testb:maxpartialdegree() + trialb:maxpartialdegree()
    var x, w = testb:quadraturerule(A, deg)
    var q = range.zip(x, w)
    var rn = range.product(testb, trialb)
        >> range.transform([
            terra(v: B1.value_t, u: B2.value_t, q: &q.type)
                return l2inner(v, u, q)
            end
        ],
        {q = &q})
    rn:collect(m)
end

local terraform MaxwellianFluxIntegrator(
    A,
    testb: &B1,
    trialb: &B2,
    bg,
    normal: &N,
    specular: bool,
    m: &M
) where {
    B1, B2, N, M
}
    var deg = testb:maxpartialdegree() + trialb:maxpartialdegree()
    var hs = [HalfSpaceQuadrature(M.traits.eltype)].new(&normal[0])
    var x, w = hs:maxwellian(A, deg + 1, bg.rho, &bg.u, bg.theta)
    var flux = lambda.new([
            terra(v: &M.traits.eltype, normal: &N)
                var res: M.traits.eltype = 0
                escape
                    for k = 0, VDIM - 1 do
                        emit quote res = res + v[k] * normal[k] end
                    end
                end
                return res
            end
        ],
        {normal = normal})
    var tensor = range.product(testb, trialb)
    if not specular then
        var q = range.zip(x, w)
        var quadrange = tensor
            >> range.transform([
                terra(v: B1.value_t, u: B2.value_t, flux: &flux.type, q: &q.type)
                    return l2inner(flux, v, u, q)
                end
                ],
                {flux = &flux, q = &q})
        quadrange:collect(m)
    else
        escape
            local T = M.traits.eltype
            local xval = {}
            for i = 1, VDIM do
                xval[i] = symbol(T)
            end
            emit quote
                var xspec = x
                    >> range.transform([
                        terra([xval], normal: normal.type)
                            escape
                                local vn = symbol(T)
                                emit quote var [vn] = 0 end
                                for i = 1, VDIM do
                                    emit quote
                                        [vn] = (
                                            [vn] + [ xval[i] ] * normal[i - 1]
                                        )
                                    end
                                end
                                local res = {}
                                for i = 1, VDIM do
                                    res[i] = quote in
                                        [ xval[i] ] - 2 * [vn] * normal[i - 1]
                                    end
                                end
                                emit quote return [res] end
                            end
                        end
                    ],
                    {normal = normal}
                )
                var quadrange = tensor
                    >> range.transform([
                        terra(
                            v: B1.value_t,
                            u: B2.value_t,
                            flux: &flux.type,
                            w: &w.type,
                            x: &x.type,
                            xspec: &xspec.type
                        )
                            return l2inner(flux, v, u, w, x, xspec)
                        end
                        ],
                        {
                            flux = &flux,
                            w = &w,
                            x = &x,
                            xspec = &xspec
                        }
                    )
                quadrange:collect(m)
            end
        end
    end
end

testenv "Mass matrix" do
    terracode
        var A: alloc.DefaultAllocator()
    end

    testset "Shifted basis in full space" do
        terracode
            var bg = background.new(1.0, {1.0, -2.5, 3.25}, 0.75)
            var pte = [darray.DynamicMatrix(int32)].from(
                &A,
                {
                    {0, 0, 0},
                    {1, 0, 0},
                    {0, 1, 0},
                    {0, 0, 1},
                    {2, 0, 0},
                    {0, 2, 0},
                    {0, 0, 2}
                }
            )
            var testb = MonomialBasis.new(pte, bg)

            var ptr = [darray.DynamicMatrix(int32)].from(
                &A, {{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, 0, 1}, {2, 2, 2}}
            )
            var trialb = MonomialBasis.new(ptr, bg)
            var mass = [darray.DynamicMatrix(double)].new(&A, {7, 5})
            MaxwellianIntegrator(&A, &testb, &trialb, bg, &mass)
            var massref = [darray.DynamicMatrix(double)].from(
                &A,
                {
                    {1, 0, 0, 0, 1},
                    {0, 1, 0, 0, 0},
                    {0, 0, 1, 0, 0},
                    {0, 0, 0, 1, 0},
                    {1, 0, 0, 0, 3},
                    {1, 0, 0, 0, 3},
                    {1, 0, 0, 0, 3}
                }
            )
        end
        for i = 0, 6 do
            for j = 0, 4 do
                test tmath.isapprox(mass(i, j), massref(i, j), 1e-14)
            end
        end
    end

    testset "Shifted basis in half space" do
        terracode
            var bg = background.new(1.0, {1.0, -2.5, 3.25}, 0.75)
            var normal = arrayof(double, 2.0 / 7.0, 3.0 / 7.0, 6.0 / 7.0)
            var pte = [darray.DynamicMatrix(int32)].from(
                &A,
                {
                    {0, 0, 0},
                    {1, 0, 0},
                    {0, 1, 0},
                    {0, 0, 1}
                }
            )
            var testb = MonomialBasis.new(pte, bg)

            var ptr = [darray.DynamicMatrix(int32)].from(
                &A,
                {
                    {0, 0, 0},
                    {1, 0, 0},
                    {0, 1, 0},
                    {0, 0, 1},
                    {2, 0, 0},
                    {0, 2, 0},
                    {0, 0, 2}
                }
            )

            var trialb = MonomialBasis.new(ptr, bg)
            var mass = [darray.DynamicMatrix(double)].new(&A, {4, 7})
            var bgh = background.new(1.0, {1e-2, 0.0, 0.0}, 1.375)
            MaxwellianFluxIntegrator(&A, &testb, &trialb, bgh, &normal[0], false, &mass)
            var massref = [darray.DynamicMatrix(double)].from(
                &A,
                {
                    {0.46923124989104753,-0.3091462289299536,1.695439640446213,-1.079148728314458,1.0238799712985998,6.896146660287203,2.98162352913931},
                    {-0.3091462289299536,1.0238799712985998,-1.177096678431062,0.5908200082503707,-1.750502822226544,-4.966743477048509,-1.368282370282976},
                    {1.695439640446213,-1.177096678431062,6.896146660287203,-4.0794530536647615,3.78591492084042,30.498989080979694,11.667462387526047},
                    {-1.079148728314458,0.5908200082503707,-4.0794530536647615,2.98162352913931,-2.181936879596525,-17.129866024330788,-9.025732823750863}
                }
            )
        end
        for i = 0, 3 do
            for j = 0, 6 do
                test tmath.isapprox(mass(i, j), massref(i, j), 1e-13)
            end
        end
    end

    testset "Shifted basis in half space with specular reflection" do
        terracode
            var bg = background.new(1.0, {1.0, -2.5, 3.25}, 0.75)
            var normal = arrayof(double, 2.0 / 7.0, 3.0 / 7.0, 6.0 / 7.0)
            var pte = [darray.DynamicMatrix(int32)].from(
                &A,
                {
                    {0, 0, 0},
                    {1, 0, 0},
                    {0, 1, 0},
                    {0, 0, 1}
                }
            )
            var testb = MonomialBasis.new(pte, bg)

            var ptr = [darray.DynamicMatrix(int32)].from(
                &A,
                {
                    {0, 0, 0},
                    {1, 0, 0},
                    {0, 1, 0},
                    {0, 0, 1},
                    {2, 0, 0},
                    {0, 2, 0},
                    {0, 0, 2}
                }
            )

            var trialb = MonomialBasis.new(ptr, bg)
            var mass = [darray.DynamicMatrix(double)].new(&A, {4, 7})
            var bgh = background.new(1.0, {1e-2, 0.0, 0.0}, 1.375)
            MaxwellianFluxIntegrator(&A, &testb, &trialb, bgh, &normal[0], true, &mass)
            var massref = [darray.DynamicMatrix(double)].from(
                &A,
                {
                    {0.46923124989104753,-0.7645450999358188,1.0123413339374154,-2.4453453413320534,2.065920157428131,2.954208440214089,13.243412064471753},
                    {-0.3091462289299536,1.2635704595402664,-0.8175609460685616,1.3098914729753715,-3.8324467439367917,-2.585282468405487,-5.542589758654284},
                    {1.695439640446213,-2.913070492356748,4.292185939398673,-9.28737449544182,7.9626216190945955,13.427730436281912,52.625432899701465},
                    {-1.079148728314458,1.457129283003149,-2.779989141535595,5.580551353397644,-3.7552894855649956,-8.710990706608396,-29.87584453894439}
                }
            )
        end
        for i = 0, 3 do
            for j = 0, 6 do
                test tmath.isapprox(mass(i, j), massref(i, j), 1e-13)
            end
        end
    end
end


local terraform nonlinear_maxwellian_inflow(
                    A,
                    testb: &B1,
                    trialb: &B2,
                    xvlhs: &C,
                    normal: &N,
                    transform
                ) where {B1, B2, C, N}
    -- For the nonlinear boundary condition we have to compute a nested
    -- integral of space and velocity. First, we discretize the spatial integral
    -- with quadrature. For this, we need the point evaluation of the spatial
    -- basis in the quadrature point, stored as a sparse matrix.
    -- With the coefficients in matrix form and the point evaluation of the spatial
    -- basis we obtain, for each quadrature point, that is row in qvlhs,
    -- the partially evaluated distribution function, that is the coefficients
    -- of the velocity basis at each quadrature point. With this information
    -- we can compute the velocity integrals.
    var nq = normal:rows()
    var nv = xvlhs:cols()
    var qvlhs = [darray.DynamicMatrix(C.traits.eltype)].zeros(A, {nq, nv})
    matrix.gemm(
        [C.traits.eltype](1),
        &trialb.space,
        xvlhs,
        [C.traits.eltype](0),
        &qvlhs
    )
    -- Qudrature for the computation of the local Maxwellian.
    -- We need to integrate a polynomial times (1, v, |v|^2) exactly.
    -- For the Gauß-Hermite quadrature we only need deg / 2 + 1 points to integrate
    -- polynomials up to degree deg exactly. We account for (1, v, |v|^2)
    -- by using two more points.
    var maxtrialdegree = trialb.velocity:maxpartialdegree()
    var xq, wq = trialb.velocity:quadraturerule(A, maxtrialdegree + 2)
    var qmaxwellian = [quote var q = range.zip(xq, wq) in &q end]
    var halfmomq = [darray.DynamicMatrix(C.traits.eltype)].zeros(
                                                        A,
                                                        {nq,
                                                        testb:nvelocitydof()}
                                                    )
    var qrange = [range.Unitrange(int64)].new(0, nq)
    var half = lambda.new(
            [
                terra(
                    i: int64,
                    A: A.type,
                    transform: transform.type,
                    qvlhs: qvlhs.type,
                    testb: testb.type,
                    trialb: trialb.type,
                    qmaxwellian: qmaxwellian.type,
                    normal: normal.type,
                    halfmomq: halfmomq.type
                )
                    var lhs = (
                        [
                            darray.DynamicVector(C.traits.eltype)
                        ].new(A, qvlhs:cols())
                    )
                    for j = 0, qvlhs:cols() do
                        lhs(j) = qvlhs(i, j)
                    end
                    var rho, u, theta = local_maxwellian(
                                            &trialb.velocity, &lhs, qmaxwellian
                                        )

                    var un: rho.type = 0
                    escape
                        for j = 1, VDIM do
                            emit quote un = un + u(j - 1) * normal(i, j - 1) end
                        end
                    end
                    var mach = un / tmath.sqrt(2 * theta)
                    var inflow = -rho * tmath.sqrt(theta / (2 * tmath.pi)) * (
                        tmath.exp(-mach * mach)
                        - tmath.sqrt(tmath.pi) * mach * (1 - tmath.erf(mach))
                    )

                    var outmom = [
                        darray.DynamicVector(C.traits.eltype)
                    ].new(A, trialb:nvelocitydof())
                    var innormal: N.traits.eltype[VDIM]
                    escape
                        for j = 1, VDIM do
                            emit quote innormal[j - 1] = -normal(i, j - 1) end
                        end
                    end

                    var rhob: C.traits.eltype = trialb.velocity.bg.rho
                    var ub: sarray.StaticVector(C.traits.eltype, VDIM)
                    escape
                        for j = 1, VDIM do
                            emit quote ub(j - 1) = trialb.velocity.bg.u(j - 1) end
                        end
                    end
                    var thetab: C.traits.eltype = trialb.velocity.bg.theta
                    maxwellian_inflow(
                        A,
                        trialb,
                        rhob,
                        ub,
                        thetab,
                        &innormal[0],
                        &outmom(0)
                    )
                    var outflow = outmom:dot(&lhs)

                    transform(&rho, &u, &theta, inflow, outflow)

                    maxwellian_inflow(
                        A,
                        testb,
                        rho,
                        u,
                        theta,
                        &normal(i, 0),
                        &halfmomq(i, 0)
                    )
                end
            ],
            {
                A = A,
                transform = transform,
                qvlhs = qvlhs, 
                testb = testb,
                trialb = trialb,
                qmaxwellian = qmaxwellian,
                normal = normal,
                halfmomq = halfmomq
            }
        )

    thread.parfor(A, qrange, half)
    var halfmom = [darray.DynamicMatrix(C.traits.eltype)].zeros(
                                                        A,
                                                        {testb:nspacedof(),
                                                        testb:nvelocitydof()}
                                                    )

    matrix.gemm([C.traits.eltype](1), &testb.space, &halfmomq, [C.traits.eltype](0), &halfmom)

    return halfmom
end

local PrepareLinearInput = terralib.memoize(function(T, I)
    local Alloc = alloc.Allocator
    local tMat = darray.DynamicMatrix(T)
    local iMat = darray.DynamicMatrix(I)
    local terra prepare_linear_input(
        -- Scaling of the background Maxwellian
        ensrho: T,
        ensU: &T,
        enstheta: T,
        -- Number of test functions in velocity
        ntestv: int32,
        -- Number of trial function in velocity
        ntrialv: int32,
        -- Monomial powers of polynomials
        test_powers: &I,
        trial_powers: &I,
        -- Scaling of the boundary Maxwellian
        bndrho: T,
        bndU: &T,
        bndtheta: T,
        normal: &T,
        -- Reflection of trial functions
        specular: bool,
        -- Pointer to matrix of size ntestv x ntrialv
        res: &T
    )
        var ensbg = background.new(ensrho, ensU, enstheta)
        var btest = MonomialBasis.new(
            __move__(iMat.frombuffer({ntestv, VDIM}, test_powers)), ensbg
        )
        var btrial = MonomialBasis.new(
            __move__(iMat.frombuffer({ntrialv, VDIM}, trial_powers)), ensbg
        )
        var bndbg = background.new(bndrho, bndU, bndtheta)
        var resmat = tMat.frombuffer({ntestv, ntrialv}, res)

        return btest, btrial, bndbg, normal, specular, resmat
    end

    return prepare_linear_input
end)

local GenerateLinearBCWrapper = terralib.memoize(function()
    local T = double
    local I = int32
    local prepare_linear_input = PrepareLinearInput(T, I)
    local sym = prepare_linear_input.type.parameters:map(symbol)

    local terra impl([sym])
        var default: alloc.DefaultAllocator()
        var testb, trialb, bndbg, normal, specular, res = (
            prepare_linear_input([sym])
        )
        MaxwellianFluxIntegrator(
            &default, &testb, &trialb, &bndbg, normal, specular, &res
        )
    end

    return impl
end)

local PrepareNonLinearInput = terralib.memoize(function(T, I)
    local Alloc = alloc.Allocator
    local spanVDIM = span.Span(T, VDIM)
    local terra prepare_nonlinear_input(
        A: Alloc,
        -- Dimension of test space and the result arrays
        ntestx: int32,
        ntestv: int32,
        -- Dimension of trial space and the input arrays
        ntrialx: int32,
        ntrialv: int32,
        -- Basis coefficients
        val: &T,
        -- Direction of derivative for basis coefficients
        tng: &T,
        -- Number of spatial quadrature points
        nqx: int32,
        -- Spatial dimension
        ndim: int32,
        -- Sampled normals
        normalq: &T,
        -- Point evaluation of spatial test functions at quadrature points transposed
        testnnz: int32,
        testdata: &T,
        testrow: &I,
        testcolptr: &I,
        -- Point evaluation of spatial trial functions at quadrature points
        trialnnz: int32,
        trialdata: &T,
        trialcol: &I,
        trialrowptr: &I,
        -- Maxwellian background
        rho: T,
        u: &T,
        theta: T,
        -- Monomial powers of polynomial approximation in velocity
        test_powers: &I,
        trial_powers: &I
    )
        var testbasis = [TensorBasis(dual.DualNumber(T))].frombuffer(
                                                            A,
                                                            true,
                                                            ntestx,
                                                            nqx,
                                                            testnnz,
                                                            testdata,
                                                            testrow,
                                                            testcolptr,
                                                            ntestv,
                                                            test_powers,
                                                            rho,
                                                            [spanVDIM](u),
                                                            theta
                                                        )
        var trialbasis = [TensorBasis(dual.DualNumber(T))].frombuffer(
                                                            A,
                                                            false,
                                                            nqx,
                                                            ntrialx,
                                                            trialnnz,
                                                            trialdata,
                                                            trialcol,
                                                            trialrowptr,
                                                            ntrialv,
                                                            trial_powers,
                                                            rho,
                                                            [spanVDIM](u),
                                                            theta
                                                        )

        var normal = [darray.DynamicMatrix(dual.DualNumber(T))].zeros(
                                                                    A,
                                                                    {nqx,
                                                                     VDIM}
                                                                )
        for i = 0, nqx do
            for j = 0, ndim do
                normal(i, j) = normalq[j + i * ndim]
            end
        end
        -- When solving the linear systems arising from Newton's method for
        --
        -- F(x) = 0
        --
        -- iteratively, we need to compute matrix-vector products of the form
        --
        -- F'(x) t
        --
        -- at a given point x and a direction t. This is equivalent to
        --
        -- d/d eps [ F(x + t eps) ] |_{eps = 0},
        --
        -- which is exactly what is computed when evaluating F with dual numbers.
        -- For the specific case of the Boltzmann equation, we use a tensor product
        -- of a spatial basis and a polynomial basis in velocity. Thus, the natural
        -- way to represent the unknown coefficients and their dual number
        -- representation is in matrix form with the spatial dof as row and the
        -- velocity dof as column indices.
        var xvlhs = [darray.DynamicMatrix(dual.DualNumber(T))].new(
                                                                    A,
                                                                    {ntrialx,
                                                                     ntrialv}
                                                                )
        for i = 0, ntrialx do
            for j = 0, ntrialv do
                var idx = j + ntrialv * i
                xvlhs(i, j) = [dual.DualNumber(T)] {val[idx], tng[idx]}
            end
        end
        return testbasis, trialbasis, xvlhs, normal
    end
    return prepare_nonlinear_input
end)

local GenerateNonLinearBCWrapper = terralib.memoize(function(Transform)
    local T = double
    local I = int32
    local prepare_nonlinear_input = PrepareNonLinearInput(T, I)
    local types = prepare_nonlinear_input.type.parameters
    -- remove the the alloc argument from the parameter list for the C wrapper
    local sym = types:map(function(T) return symbol(T) end):sub(2, -1)
    local cap = Transform.entries:map(
        function(tab)
            return symbol(tab.type)
        end
    )

    local terra impl([sym], resval: &T, restng: &T, [cap])
        var default: alloc.DefaultAllocator()
        var testbasis, trialbasis, xvlhs, normal = (
            prepare_nonlinear_input(&default, [sym])
        )
        var transform = [Transform] {[cap]}
        var res = (
            nonlinear_maxwellian_inflow(
                &default,
                &testbasis,
                &trialbasis,
                &xvlhs,
                &normal,
                &transform
            )
        )
        var idx = 0
        for i = 0, res:rows() do
            for j = 0, res:cols() do
                resval[idx] = res(i, j).val
                restng[idx] = res(i, j).tng
                idx = idx + 1
            end
        end
    end
    return impl
end)

local FixedPressure = terralib.memoize(function(T)
    local struct fixed_pressure{
        pressure: T
    }
    fixed_pressure.metamethods.__apply = macro(function(self, ...)
        local arg = {...}
        local terraform apply(self, rho, u, theta, inflow, outflow)
            var pressure = self.pressure
            @rho = pressure / @theta
        end
        return `apply(self, [arg])
    end)
    return fixed_pressure
end)

local FixedMassFlowRate = terralib.memoize(function(T)
    local struct fixed_mass_flow_rate{
        mflow: T
    }
    fixed_mass_flow_rate.metamethods.__apply = macro(function(self, ...)
        local arg = {...}
        local terraform apply(self, rho, u, theta, inflow, outflow)
            var mflow = self.mflow
            inflow = inflow / @rho
            @rho = -(mflow + outflow) / inflow
        end
        return `apply(self, [arg])
    end)
    return fixed_mass_flow_rate
end)

return {
    HalfSpaceQuadrature = HalfSpaceQuadrature,
    GenerateNonLinearBCWrapper = GenerateNonLinearBCWrapper,
    PrepareNonLinearInput = PrepareNonLinearInput,
    GenerateLinearBCWrapper = GenerateLinearBCWrapper,
    PrepareLinearInput = PrepareLinearInput,
    FixedPressure = FixedPressure,
    FixedMassFlowRate = FixedMassFlowRate,
}
