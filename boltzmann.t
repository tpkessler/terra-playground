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
local dmatrix = require("dmatrix")
local tmath = require("mathfuns")
local dual = require("dual")
local range = require("range")
local gauss = require("gauss")
local halfhermite = require("halfrangehermite")
local lambda = require("lambda")
local tmath = require("mathfuns")
local sparse = require("sparse")
local stack = require("stack")
local qr = require("qr")

local VDIM = 3

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

terra MonomialBasis:maxpartialdegree()
    var maxdeg = -1
    var p = self.p
    for i = 0, p:rows() do
        for j = 0, p:cols() do
            maxdeg = tmath.max(maxdeg, p(i, j))
        end
    end
    return maxdeg
end

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

local Vector = concepts.Vector
local Number = concepts.Number
local local_maxwellian
terraform local_maxwellian(basis, coeff: &V, quad)
    where {I: concepts.Integral, V: Vector(Number)}
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
local Stack = concepts.Stack(Number)
RecDiff.methods.getcoeff = {&RecDiff, concepts.Integral, &Stack} -> {}
RecDiff.methods.getinit = {&RecDiff, &Stack} -> {}

local Integer = concepts.Integer
local olver
terraform olver(alloc, rec: &R, yn: &V)
    where {R: RecDiff, S: Stack, V: Vector(Number)}
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
            [terra(i: int, n: int): I.traits.eltype
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
    impl.metamethods.__typename = function(self)
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
    function impl.metamethods.__typename(self)
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
    impl.metamethods.__typename = function(self)
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
    terraform reverse(w: &V) where {V: Vector(concepts.Any)}
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
    terraform castvector(dest: &V1, src: &V2)
        where {V1: Vector(concepts.Any), V2: Vector(concepts.Any)}
        (
            @src >> range.transform([
                terra(x: V2.eltype)
                    return [V1.eltype](x)
                end
            ])
        ):collect(dest)
    end

    local normalize
    terraform normalize(v: &V) where {V: Vector(concepts.Real)}
        var nrmsqr = v:dot(v) + 1e-15
        v:scal(1 / tmath.sqrt(nrmsqr))
    end

    local householder
    terraform householder(v: &V1, h: &V2)
        where {V1: Vector(Number), V2: Vector(Number)}
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

local DefaultAlloc = alloc.DefaultAllocator()
local dualDouble = dual.DualNumber(double)
local ddVec = dvector.DynamicVector(dualDouble)
local ddMat = dmatrix.DynamicMatrix(dualDouble)
local ddStack = stack.DynamicStack(dualDouble)
local CSR = sparse.CSRMatrix(dualDouble, int32)
local HalfSpaceDual = HalfSpaceQuadrature(dualDouble)

local TensorBasis = terralib.memoize(function(T)
    local I = int32
    local iMat = dmatrix.DynamicMatrix(I)
    local CSR = sparse.CSRMatrix(T, I)
    local Stack = stack.DynamicStack(T)
    local struct tensor_basis {
        space: CSR
        velocity: MonomialBasis
        cast: Stack
    }

    tensor_basis.metamethods.__typename = function(self)
        return ("TensorBasis(%s)"):format(tostring(T))
    end

    base.AbstractBase(tensor_basis)

    terra tensor_basis:nspacedof()
        return self.space:cols()
    end

    terra tensor_basis:nvelocitydof()
        return self.velocity.p:rows()
    end

    terra tensor_basis:ndof()
        return self:nspacedof() * self:nvelocitydof()
    end

    tensor_basis.staticmethods.new = terra(b: CSR, p: iMat)
        return tensor_basis {b, MonomialBasis.new(p)}
    end

    terraform tensor_basis.staticmethods.frombuffer(
        alloc,
        nq: I,
        nx: I,
        nnz: I,
        data: &S,
        col: &int32,
        rowptr: &I,
        nv: I,
        ptr: &I)
        where {S: concepts.Number}
        var cast = Stack.new(alloc, nnz)
        for i = 0, nnz do
            -- Explicit cast as possibly S ~= T
            cast:push(data[i])
        end
        var space = CSR.frombuffer(nq, nx, nnz, &cast(0), col, rowptr)
        var tb: tensor_basis
        tb.space = space
        tb.cast = cast

        tb.velocity = iMat.frombuffer(nv, VDIM, ptr, VDIM)

        return tb
    end

    return tensor_basis
end)

-- local terraform outflow_impl()

local TensorBasisDual = TensorBasis(dualDouble)
local terra outflow(
    num_threads: int64,
    -- Dimension of test space and the result arrays
    ntestx: int64,
    ntestv: int64,
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
    testnnz: int32,
    testdata: &double,
    testrow: &int32,
    testcolptr: &int32,
    -- Point evaluation of spatial trial functions at quadrature points
    trialnnz: int32,
    trialdata: &double,
    trialcol: &int32,
    trialrowptr: &int32,
    -- Monomial powers of polynomial approximation in velocity
    test_powers: &int32,
    trial_powers: &int32
)
    var alloc: DefaultAlloc
    var trialbasis = TensorBasisDual.frombuffer()
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
    var xvlhs = ddMat.new(&alloc, ntrialx, ntrialv)
    for i = 0, ntrialx do
        for j = 0, ntrialv do
            var idx = j + ntrialv * i
            xvlhs(i, j) = dualDouble {val[idx], tng[idx]}
        end
    end

    -- The nonlinear boundary condition that we have to compute is a nested
    -- integral of space and velocity. First, we discretize the spatial integral
    -- with quadrature. For this, we need the point evaluation of the spatial
    -- basis in the quadrature point, stored as a sparse matrix.
    var dualtrialdata = ddStack.new(&alloc, trialnnz)
    for i = 0, trialnnz do
        -- Explicit cast from double to dual double as we perform matrix-matrix
        -- multiplications with coefficients stored as dual doubles.
        dualtrialdata:push(trialdata[i])
    end
    var qxtrial = CSR.frombuffer(
                    nqx, ntrialx, trialnnz,
                    &dualtrialdata(0), trialcol, trialrowptr
                  )
    -- With the coefficients in matrix form and the point evaluation of the spatial
    -- basis we obtain, for each quadrature point, that is row in qvlhs,
    -- the partially evaluated distribution function, that is the coefficients
    -- of the velocity basis at each quadrature point. With this information
    -- we can compute the velocity integrals.
    var qvlhs = ddMat.zeros(&alloc, nqx, ntrialv)
    qvlhs:mul([dualDouble](0), [dualDouble](1), false, &qxtrial, false, &xvlhs)

    -- Qudrature for the computation of the local Maxwellian.
    -- We need to integrate a polynomial times (1, v, |v|^2) exactly.
    -- For the Gauß-Hermite quadrature we only need deg / 2 + 1 points to integrate
    -- polynomials up to degree deg exactly. We account for (1, v, |v|^2)
    -- by using two more points.
    var ptrial = iMat.frombuffer(ntrialv, VDIM, trial_powers, VDIM)
    var trialbasis = MonomialBasis.new(ptrial)
    var maxtrialdegree = trialbasis:maxpartialdegree()
    var q1dmaxwellian = gauss.hermite(
                        &alloc,
                        maxtrialdegree / 2 + 1 + 2,
                        {origin = 0.0, scaling = tmath.sqrt(2.)}
                      )
    var qmaxwellian = escape 
        local arg = {}
        for i = 1, VDIM do
            arg[i] = `&q1dmaxwellian
        end
        emit quote
                 var p = gauss.productrule([arg])
             in
                 range.zip(&p.x, &p.w)
             end
    end

    var lhs = ddVec.new(&alloc, qvlhs:cols())
    var ptest = iMat.frombuffer(ntestv, VDIM, test_powers, VDIM)
    var testbasis = MonomialBasis.new(ptest)
    var maxtestdegree = testbasis:maxpartialdegree()
    var halfmom = ddMat.new(&alloc, qvlhs:rows(), ptest:rows())

    for i = 0, qvlhs:rows() do
        for j = 0, qvlhs:cols() do
            lhs(j) = qvlhs(i, j)
        end
        var rho, u, theta = local_maxwellian(&trialbasis, &lhs, &qmaxwellian)
        var loc_normal: dualDouble[VDIM]
        for k = 0, ndim do
            -- The half space quadrature is defined on the positive half space,
            -- dot(v, n) > 0. For the boundary condition we need to compute
            -- the integral over the inflow part of the boundary, that is
            -- dot(v, n) < 0. One way to archive is to define the half space
            -- with the negative normal, -n.
            loc_normal[k] = -normal[k + ndim * i]
        end
        for k = ndim, VDIM do
            loc_normal[k] = 0
        end
        var hs = HalfSpaceDual.new(&loc_normal[0])
        -- include one extra point for flux weight dot(v, n)
        var qhalf = escape
            emit quote
                var x, w = (
                    hs:maxwellian(&alloc, maxtestdegree + 1, rho, &u, theta)
                )
            in
                range.zip(x, w)
            end
        end
        var vn = lambda.new([
                terra(x: &dualDouble, normal: &dualDouble)
                    var res: dualDouble = 0
                    escape
                        for k = 0, VDIM - 1 do
                            emit quote res = res + x[k] * normal[k] end
                        end
                    end
                    return res
                end
            ],
            {normal = &loc_normal[0]})
        for j, b in range.enumerate(testbasis) do
            -- Because we integrate over dot(v, -n) > 0 the weight dot(v, n)
            -- has the wrong sign, so we need to correct it after quadrature.
            halfmom(i, j) = -l2inner(b, vn, &qhalf)
        end
    end

    var dualtestdata = ddStack.new(&alloc, testnnz)
    for i = 0, testnnz do
        dualtestdata:push(testdata[i])
    end
    var qxtest = CSR.frombuffer(
                    nqx, ntestx, testnnz,
                    &dualtestdata(0), testrow, testcolptr
                  )
    var res = ddMat.zeros(&alloc, ntestx, ntestv)
    res:mul([dualDouble](0), [dualDouble](1), false, &qxtest, false, &halfmom)

    for i = 0, res:rows() do
        for j = 0, res:cols() do
            var idx = j + ntestv * i
            resval[idx] = res(i, j).val
            restng[idx] = res(i, j).tng
        end
    end
end

local ddStack = stack.DynamicStack(dualDouble)
local lib = terralib.includec("stdlib.h")
terra main(argc: int, argv: &rawstring)
    var alloc: DefaultAlloc
    var n = 5
    if argc > 1 then
        n = lib.strtol(argv[1], nil, 10)
    end
    var qh = gauss.hermite(&alloc, n, {origin = 0.0, scaling = tmath.sqrt(2.)})
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
terralib.saveobj("boltzmann.o", {outflow = outflow})

return {
    HalfSpaceQuadrature = HalfSpaceQuadrature,
}
