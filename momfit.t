-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local base = require("base")
local concepts = require("concepts")
local darray = require("darray")
local range = require("range")
local recdiff = require("recdiff")
local tmath = require("tmath")

import "terraform"

local Number = concepts.Number
local concept Interval(T) where {T: Number}
    Self:addentry("left", T)
    Self:addentry("right", T)
    Self.traits.eltype = T
end

local Real = concepts.Real
local Integer = concepts.Integer
local RecDiff = recdiff.RecDiff
local terraform clenshawcurtis(alloc, n: N, rec: &R, dom: &I)
    where {
        N: Integer,
        R: RecDiff(Real),
        I: Interval(Real)
    }
    var x = [darray.DynamicVector(I.traits.eltype)].new(alloc, n)
    (
        [range.Unitrange(int)].new(0, n)
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
    var mom = [darray.DynamicVector(R.traits.eltype)].zeros(alloc, nmax)
    recdiff.olver(alloc, rec, &mom)

    -- The quadrature weights on the reference domain (-1, 1) are given by
    -- the inverse DCT-III transform, that is a scaled DCT-II transform of
    -- the moments of the weight function in the Chebyshev basis.
    var w = [darray.DynamicVector(R.traits.eltype)].zeros(alloc, n)
    for i = 0, n do
        var res = mom(0) / 2
        for j = 1, n do
            var arg = tmath.pi / (2 * n) * (2 * i + 1) * j
            res = res + tmath.cos(arg) * mom(j)
        end
        w(i) = res
    end
    w:scal([I.traits.eltype](2) / n)

    var xq = [darray.DynamicVector(I.traits.eltype)].new(alloc, n)
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

    var wq = [darray.DynamicVector(I.traits.eltype)].new(alloc, n)
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
    local struct impl {
        a: T
    }
    function impl.metamethods.__typename(self)
        return ("ExpMom(%s)"):format(tostring(T))
    end
    base.AbstractBase(impl)
    impl.traits.depth = 5
    impl.traits.ninit = 2
    impl.traits.eltype = T

    local Integer = concepts.Integer
    local Stack = concepts.Stack 
    terraform impl:getcoeff(n: I, y: &S) where {I: Integer, S: Stack(T)}
        var a = self.a
        y:set(0, -a * (n + 1))
        y:set(1, -2 * a * (n + 1))
        y:set(2, -2 * (a + n * n - 1))
        y:set(3, 2 * a * (n - 1))
        y:set(4, a * (n - 1))
        y:set(5, 2 * (tmath.exp(-4 * a) + terralib.select(n % 2 == 0, 1, -1)))
    end

    local Stack = concepts.Stack 
    terraform impl:getinit(y: &S) where {S: Stack(T)}
        var a = self.a
        var arg = 2 * tmath.sqrt(a)
        var y0 = tmath.sqrt(tmath.pi) * tmath.fderf(arg) 
        var y1 = -y0 + 2 * tmath.fdexpm1(-4 * a)
        y:set(0, y0)
        y:set(1, y1)
    end
    impl.staticmethods.new = terra(a: T)
        return impl {a}
    end
    return impl
end)

local ConstMom = terralib.memoize(function(T)
    local struct impl {}
    base.AbstractBase(impl)
    impl.traits.depth = 3
    impl.traits.ninit = 1
    impl.traits.eltype = T

    local Integer = concepts.Integer
    local Stack = concepts.Stack 
    terraform impl:getcoeff(n: I, y: &S) where {I: Integer, S: Stack(T)}
        var val: T
        if n == 0 then
            val = 2
        elseif n % 2 == 0 then
            val = [T](-2) / (n * n - 1)
        else
            val = 0
        end
        y:set(0, 0)
        y:set(1, 1)
        y:set(2, 0)
        y:set(3, val)
    end

    local Stack = concepts.Stack 
    terraform impl:getinit(y: &S) where {S: Stack(T)}
        y:set(0, 2)
    end

    impl.staticmethods.new = terra()
        return impl {}
    end

    return impl
end)

return {
    Interval = Interval,
    IntervalFactory = IntervalFactory,
    clenshawcurtis = clenshawcurtis,
    ExpMom = ExpMom,
    ConstMom = ConstMom,
}
