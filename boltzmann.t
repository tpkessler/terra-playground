-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"

local alloc = require("alloc")
local base = require("base")
local concepts = require("concepts")
local svector = require("svector")
local dvector = require("dvector")
local matrix = require("matrix")
local dmatrix = require("dmatrix")
local tmath = require("mathfuns")
local dual = require("dual")
local range = require("range")
local gauss = require("gauss")
local halfhermite = require("halfrangehermite")
local lambda = require("lambda")
local tmath = require("mathfuns")
local thread = require("thread")
local momfit = require("momfit")
local sparse = require("sparse")
local stack = require("stack")
local qr = require("qr")

local VDIM = 3

local pow
terraform pow(n: I, x: T) where {I: concepts.Integer, T: concepts.Real}
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
terraform monomial(v: &T, p: &I) where {I: concepts.Integer, T: concepts.Number}
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

terra MonomialBasis:maxpartialdegree()
    var maxdeg = -1
    for i = 0, self.p:rows() do
        for j = 0, self.p:cols() do
            maxdeg = tmath.max(maxdeg, self.p(i, j))
        end
    end
    return maxdeg
end

MonomialBasis.staticmethods.new = terra(p: iMat)
    var basis: MonomialBasis
    basis.p = __move__(p)
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
    range.Base(MonomialBasis, iterator)
end

local TensorBasis = terralib.memoize(function(T)
    local I = int32
    local iMat = dmatrix.DynamicMatrix(I)
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

    tensor_basis.staticmethods.new = terra(b: CSR, transposed: bool, p: iMat)
        var tb : tensor_basis
        tb.space = __move__(b)
        tb.transposed = transposed
        tb.velocity = MonomialBasis.new(__move__(p))
        return tb
    end

    terraform tensor_basis.staticmethods.frombuffer(
        alloc,
        transposed: bool,
        nq: I1,
        nx: I2,
        nnz: I3,
        data: &S,
        col: &int32,
        rowptr: &I,
        nv: I4,
        ptr: &I)
        where {
                S: concepts.Number,
                I1: concepts.Integer,
                I2: concepts.Integer,
                I3: concepts.Integer,
                I4: concepts.Integer
              }
        var cast = Stack.new(alloc, nnz)
        for i = 0, nnz do
            -- Explicit cast as possibly S ~= T
            cast:push(data[i])
        end
        var tb: tensor_basis
        tb.space = CSR.frombuffer(nq, nx, nnz, &cast(0), col, rowptr)
        tb.transposed = transposed
        tb.velocity = MonomialBasis.new(__move__(iMat.frombuffer(nv, VDIM, ptr, VDIM)))
        tb.cast = __move__(cast)

        return tb
    end

    return tensor_basis
end)

local terraform l2inner(f, g, q: &Q) where {Q}
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

local Vector = concepts.Vector
local Number = concepts.Number
local terraform local_maxwellian(basis, coeff: &V, quad: &Q)
    where {V: Vector(Number), Q}
    var m1: V.traits.eltype = 0
    var m2 = [svector.StaticVector(V.traits.eltype, VDIM)].zeros()
    var m3: V.traits.eltype = 0

    var it = quad:getiterator()
    var xref, wref = it:getvalue()
    for bc in range.zip(basis, coeff) do
        var cnst = lambda.new([terra(v: &wref.type) return 1.0 end])
        m1 = m1 + l2inner(bc._0, cnst, quad) * bc._1
        escape
            for i = 0, VDIM - 1 do
                local vi = `lambda.new([terra(v: &wref.type) return v[i] end])
                emit quote
                    m2(i) = m2(i) + l2inner(bc._0, [vi], quad) * bc._1
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

local HalfSpaceQuadrature = terralib.memoize(function(T)
    local SVec = svector.StaticVector(T, VDIM)
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

    local reverse
    terraform reverse(w: &V) where {V: Vector(concepts.Any)}
        for i = 0, w:size() / 2 do
            var j = w:size() - 1 - i
            var tmp = w(i)
            w(i) = w(j)
            w(j) = tmp
        end
    end

    local ExpMomT = momfit.ExpMom(T)
    local IntT = momfit.IntervalFactory(T)
    local VecT = dvector.DynamicVector(T)

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
        for i = 0, v:size() do
            v(i) = v(i) - 2 * dot * h(i)
        end
    end

    local Integer = concepts.Integer
    local Stack = concepts.Stack
    terraform impl:maxwellian(alloc, n: N, rho: T, u: &S, theta: T)
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
        var qfinite = momfit.clenshawcurtis(alloc, n, &rec, &dom)
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

        var xnormal = range.join(__move__(xfinite), __move__(xhalf))
        var wnormal = range.join(__move__(wfinite), __move__(whalf))

        var qhermite = gauss.hermite(
            alloc,
            nhalf,
            {origin = 0, scaling = tmath.sqrt(2.0)}
        )
        var xhermite = VecT.new(alloc, nhalf)
        var whermite = VecT.new(alloc, nhalf)
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
        var yhermite = VecT.like(alloc, &xhermite)
        yhermite:copy(&xhermite)
        var points = range.product(
                        __move__(xnormal),
                        __move__(xhermite),
                        __move__(yhermite)
                     )
                     >> range.transform([
                        terra(
                            x1: T,
                            x2: T,
                            x3: T,
                            u: &S,
                            theta: T,
                            diff: SVec
                        )
                            -- First rotate the quadrature points from the
                            -- reference half space to the half space defined
                            -- by the given normal ...
                            var x = SVec.from(x1, x2, x3)
                            householder(&x, &diff)
                            var y: x.type
                            -- ... and then shift and scale with the velocity
                            -- and the temperature of the local Maxwellian.
                            escape
                                local ret = {}
                                for i = 0, VDIM - 1 do
                                    emit quote
                                        y(i) = tmath.sqrt(theta) * x(i) + u(i)
                                    end
                                    ret[i + 1] = `y(i)
                                end
                                emit quote return [ret] end
                            end
                        end
                    ], {u = u, theta = theta, diff = diff})

        var wyhermite = VecT.like(alloc, &whermite)
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
                    alloc,
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
    var qhalf = escape
        emit quote
            -- include one extra point for flux weight dot(v, n)
            var x, w = (
                hs:maxwellian(alloc, maxtestdegree + 1, rho, &u, theta)
            )
        in
            range.zip(&x, &w)
        end
    end
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

local terraform nonlinear_maxwellian_inflow(
                    alloc,
                    testb: &B1,
                    trialb: &B2,
                    xvlhs: &C,
                    normal,
                    transform
                ) where {B1, B2, C}
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
    var qvlhs = [dmatrix.DynamicMatrix(C.eltype)].zeros(alloc, nq, nv)
    matrix.scaledaddmul(
        [C.eltype](1),
        false,
        &trialb.space,
        false,
        xvlhs,
        [C.eltype](0),
        &qvlhs
    )
    -- Qudrature for the computation of the local Maxwellian.
    -- We need to integrate a polynomial times (1, v, |v|^2) exactly.
    -- For the Gauß-Hermite quadrature we only need deg / 2 + 1 points to integrate
    -- polynomials up to degree deg exactly. We account for (1, v, |v|^2)
    -- by using two more points.
    var maxtrialdegree = trialb.velocity:maxpartialdegree()
    var vhermite, whermite = gauss.hermite(
                            alloc,
                            maxtrialdegree / 2 + 1 + 2,
                            {origin = 0.0, scaling = tmath.sqrt(2.)}
                      )
    whermite:scal(1 / tmath.sqrt(2 * tmath.pi))
    var qmaxwellian = escape 
        local arg = {}
        for i = 1, VDIM do
            arg[i] = quote
                         var q = gauss.hermite_t {vhermite, whermite}
                     in
                         &q
                     end
        end
        emit quote
                var p = gauss.productrule([arg])
                var rn = range.zip(&p.x, &p.w)
             in
                 &rn
             end
    end

    var halfmomq = [dmatrix.DynamicMatrix(C.eltype)].new(
                                                        alloc,
                                                        nq,
                                                        testb:nvelocitydof()
                                                    )
    var qrange = [range.Unitrange(int64)].new(0, nq)
    thread.parfor(alloc, qrange, lambda.new(
            [
                terra(
                    i: int64,
                    alloc: alloc.type,
                    transform: transform.type,
                    nv: nv.type,
                    qvlhs: qvlhs.type,
                    testb: testb.type,
                    trialb: trialb.type,
                    qmaxwellian: qmaxwellian.type,
                    normal: normal.type,
                    halfmomq: halfmomq.type
                )
                    var lhs = (
                        [
                            dvector.DynamicVector(C.eltype)
                        ].new(alloc, qvlhs:cols())
                    )
                    for j = 0, nv do
                        lhs(j) = qvlhs(i, j)
                    end
                    var rho, u, theta = local_maxwellian(
                                            &trialb.velocity, &lhs, qmaxwellian
                                        )
                    transform(&rho, &u, &theta)
                    maxwellian_inflow(
                        alloc,
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
                alloc = alloc,
                transform = transform,
                nv = nv,
                qvlhs = qvlhs,
                testb = testb,
                trialb = trialb,
                qmaxwellian = qmaxwellian,
                normal = normal,
                halfmomq = halfmomq
            }
        )
    )
    var halfmom = [dmatrix.DynamicMatrix(C.eltype)].zeros(
                                                        alloc,
                                                        testb:nspacedof(),
                                                        testb:nvelocitydof()
                                                    )
    matrix.scaledaddmul(
        [C.eltype](1),
        false,
        &testb.space,
        false,
        &halfmomq,
        [C.eltype](0),
        &halfmom
    )
    return halfmom
end

local PrepareInput = terralib.memoize(function(T, I)
    local Alloc = alloc.Allocator
    local terra prepare_input(
        alloc: Alloc,
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
        -- Monomial powers of polynomial approximation in velocity
        test_powers: &I,
        trial_powers: &I
    )
        var testbasis = [TensorBasis(dual.DualNumber(T))].frombuffer(
                                                            alloc,
                                                            true,
                                                            ntestx,
                                                            nqx,
                                                            testnnz,
                                                            testdata,
                                                            testrow,
                                                            testcolptr,
                                                            ntestv,
                                                            test_powers
                                                        )
        var trialbasis = [TensorBasis(dual.DualNumber(T))].frombuffer(
                                                            alloc,
                                                            false,
                                                            nqx,
                                                            ntrialx,
                                                            trialnnz,
                                                            trialdata,
                                                            trialcol,
                                                            trialrowptr,
                                                            ntrialv,
                                                            trial_powers
                                                        )

        var normal = [dmatrix.DynamicMatrix(dual.DualNumber(T))].zeros(
                                                                    alloc,
                                                                    nqx,
                                                                    VDIM
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
        var xvlhs = [dmatrix.DynamicMatrix(dual.DualNumber(T))].new(
                                                                    alloc,
                                                                    ntrialx,
                                                                    ntrialv
                                                                )
        for i = 0, ntrialx do
            for j = 0, ntrialv do
                var idx = j + ntrialv * i
                xvlhs(i, j) = [dual.DualNumber(T)] {val[idx], tng[idx]}
            end
        end
        return testbasis, trialbasis, xvlhs, normal
    end
    return prepare_input
end)

local GenerateBCWrapper = terralib.memoize(function(Transform)
    local T = double
    local I = int32
    local prepare_input = PrepareInput(T, I)
    local types = prepare_input.type.parameters
    -- remove the the alloc argument from the parameter list for the C wrapper
    local sym = types:map(function(T) return symbol(T) end):sub(2, -1)
    local cap = Transform.entries:map(
        function(tab)
            return symbol(tab.type)
        end
    )

    local DefaultAlloc = alloc.DefaultAllocator()
    local alloc = symbol(DefaultAlloc)
    local data = symbol(prepare_input.type.returntype)
    local transform = symbol(Transform)
    local refdata = {}
    for i = 1, #data.type.entries do
        refdata[i] = `&[data].["_" .. tostring(i - 1)]
    end

    local resval = symbol(&T)
    local restng = symbol(&T)
    local res = symbol(dmatrix.DynamicMatrix(dual.DualNumber(T)))
    local terra impl([sym], [resval], [restng], [cap])
        var [alloc]
        var [data] = prepare_input(&[alloc], [sym])
        var [transform] = [Transform] {[cap]}
        var [res] = (
            nonlinear_maxwellian_inflow(&[alloc], [refdata], &[transform])
        )
        var ld = [res].ld
        for i = 0, [res]:rows() do
            for j = 0, [res]:cols() do
                var idx = j + ld * i
                [resval][idx] = [res](i, j).val
                [restng][idx] = [res](i, j).tng
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
        local terraform apply(self, rho, u, theta)
            var pressure = self.pressure
            @rho = pressure / @theta
        end
        return `apply(self, [arg])
    end)
    return fixed_pressure
end)

return {
    HalfSpaceQuadrature = HalfSpaceQuadrature,
    GenerateBCWrapper = GenerateBCWrapper,
    PrepareInput = PrepareInput,
    FixedPressure = FixedPressure,
}
