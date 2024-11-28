-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"

local alloc = require("alloc")
local base = require("base")
local concept = require("concept")
local vecbase = require("vector")
local svector = require("svector")
local dvector = require("dvector")
local dmatrix = require("dmatrix")
local tmath = require("mathfuns")
local dual = require("dual")
local range = require("range")
local gauss = require("gauss")
local lambda = require("lambdas")
local tmath = require("mathfuns")
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

local monomial
terraform monomial(v: &T, p: &I) where {I: concept.Integral, T: concept.Number}
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
    var x, w = unpacktuple(xw)
    var res = [w.type](0)
    var idx = 0
    for xw in q do
        var x, w = unpacktuple(xw)
        var arg = [&w.type](&x)
        res = res + w * f(arg) * g(arg)
        idx = idx + 1
    end
    return res
end

local Vector = vecbase.Vector
local local_maxwellian
terraform local_maxwellian(basis, coeff: &V, quad)
    where {I: concept.Integral, V: Vector}
    var m1: coeff.type.type.eltype = 0
    var m2 = [svector.StaticVector(m1.type, VDIM)].zeros()
    var m3: m1.type = 0

    var it = quad:getiterator()
    var xw = it:getvalue()
    var x, w = unpacktuple(xw)
    for bc in range.zip(basis, coeff) do
        var cnst = lambda.new([terra(v: &w.type) return 1.0 end])
        m1 = m1 + l2inner(bc._0, cnst, quad) * bc._1
        escape
        -- Unroll loop instead of a dynamic loop. This would require
        -- a captured variable
            for i = 0, VDIM - 1 do
                local vi = `lambda.new([terra(v: &w.type) return v[i] end])
                emit quote m2(i) = m2(i) + l2inner(bc._0, [vi], quad) * bc._1 end
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
local io = terralib.includec("stdio.h")
terra main()
    var alloc: DefaultAlloc
    var n = 21
    var qh = hermite(&alloc, n)
    var rule = gauss.productrule(&qh, &qh, &qh)
    var quad = range.zip(&rule.x, &rule.w)
    var p = iMat.from(&alloc, {
        {2, 0, 0},
        {0, 2, 0},
        {0, 0, 2},
    })
    var basis = MonomialBasis.new(p)
    var coeff = ddVec.zeros(&alloc, p:rows())
    for i = 0, coeff:size() do
        coeff(i).val = 1.0 / 3.0
        coeff(i).tng = 1
    end
    var rho, u, theta = local_maxwellian(&basis, &coeff, &quad)
    io.printf("rho %g %g\n", rho.val, rho.tng)
    for i = 0, VDIM do
        io.printf("u(%d) %g %g\n", i, u(i).val, u(i).tng)
    end
    io.printf("theta %g %g\n", theta.val, theta.tng)
    return 0
end
main()
terralib.saveobj("boltzmann.o", {main = main})
