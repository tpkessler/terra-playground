-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"

local base = require("base")
local err = require("assert")
local concepts = require("concepts")
local tmath = require("tmath")
local lapack = require("lapack")

local Matrix = concepts.Matrix
local Vector = concepts.Vector
local Number = concepts.Number
local Integer = concepts.Integer

terraform factorize(a : &M, p : &P, tol : T)
    where {M : Matrix(Number), P : Vector(Integer), T : Number}
    var n = a:size(0)
    for i = 0, n do
        p:set(i, i)
    end
    for i = 0, n do
        var maxA = [tol.type](0)
        var imax = i
        for k = i, n do
            var absA = tmath.abs(a:get(k, i))
            if absA > maxA then
                maxA = absA
                imax = k
            end
        end

        err.assert(maxA > tol)

        if imax ~= i then
            var j = p:get(i)
            p:set(i, p:get(imax))
            p:set(imax, j)

            for k = 0, n do
                var tmp = a:get(i, k)
                a:set(i, k, a:get(imax, k))
                a:set(imax, k, tmp)
            end
        end

        for j = i + 1, n do
            a:set(j, i, a:get(j, i) / a:get(i, i))

            for k = i + 1, n do
                var tmp = a:get(j, k)
                a:set(j, k, tmp - a:get(j, i) * a:get(i, k))
            end
        end
    end
end

local BLASMatrix = concepts.BLASMatrix
local ContiguousVector = concepts.ContiguousVector
local BLASNumber = concepts.BLASNumber

terraform factorize(a: &M, p: &P, tol: T)
    where {M: BLASMatrix(BLASNumber), P: ContiguousVector(int32), T: BLASNumber}
    var n, m, adata, lda = a:getblasdenseinfo()
    err.assert(n == m)
    var np, pdata = p:getbuffer()
    err.assert(n == np)
    var info = lapack.getrf(lapack.ROW_MAJOR, n, n, adata, lda, pdata)
    return info
end

local Bool = concepts.Bool
local conj = tmath.conj
terraform solve(trans: B, a: &M, p: &P, x: &V)
    where {B: Bool, M: Matrix(Number), P: Vector(Integer), V: Vector(Number)}
    var n = a:size(0)
    if not trans then
        for i = 0, n do
            var idx = p:get(i)
            while idx < i do
                idx = p:get(idx)
            end
            var tmp = x:get(i)
            x:set(i, x:get(idx))
            x:set(idx, tmp)
        end

        for i = 0, n do
            for k = 0, i do
                x:set(i, x:get(i) - a:get(i, k) * x:get(k))
            end
        end

        for ii = 0, n do
            var i = n - 1 - ii
            for k = i + 1, n do
                x:set(i, x:get(i) - a:get(i, k) * x:get(k))
            end
            x:set(i, x:get(i) / a:get(i, i))
        end
    else
        for i = 0, n do
            for k = 0, i do
                x:set(i, x:get(i) - conj(a:get(k, i)) * x:get(k))
            end
            x:set(i, x:get(i) / conj(a:get(i, i)))
        end

        for ii = 0, n do
            var i = n - 1 - ii
            for k = i + 1, n do
                x:set(i, x:get(i) - conj(a:get(k, i)) * x:get(k))
            end
        end

        for ii = 0, n do
            var i = n - 1 - ii
            var idx = p:get(i)
            while idx < i do
                idx = p:get(idx)
            end
            var tmp = x:get(i)
            x:set(i, x:get(idx))
            x:set(idx, tmp)
        end
    end
end

local function get_trans(T)
    if concepts.Complex(T) then
        return "C"
    else
        return "T"
    end
end

local BLASVector = concepts.BLASVector
terraform solve(trans: B, a: &M, p: &P, x: &V)
    where {B: Bool, M: BLASMatrix(BLASNumber), P: ContiguousVector(int32), V: BLASVector(BLASNumber)}
    var n, m, adata, lda = a:getblasdenseinfo()
    err.assert(n == m)
    var np, pdata = p:getbuffer()
    err.assert(n == np)
    var nx, xdata, incx = x:getblasinfo()
    var lapack_trans: rawstring
    if trans then
        lapack_trans = [get_trans(M.traits.eltype)]
    else
        lapack_trans = "N"
    end
    lapack.getrs(
        lapack.ROW_MAJOR,
        @lapack_trans,
        n,
        1,
        adata,
        lda,
        pdata,
        xdata,
        incx
    )
end

local LUFactory = terralib.memoize(function(M, P)

    local T = M.traits.eltype
    local Vector = concepts.Vector(T)
    local VectorInteger = concepts.Vector(Integer)
    local Matrix = concepts.Matrix(T)
    local Factorization = concepts.Factorization(T)

    assert(Matrix(M), "Type " .. tostring(M)
                              .. " does not implement the matrix interface")
    assert(VectorInteger(P), "Type " .. tostring(P)
                              .. " does not implement the vector interface")
    
    local Ts = concepts.Complex(T) and T.traits.eltype or T
    local struct lu{
        a: &M
        p: &P
        tol: Ts
    }
    function lu.metamethods.__typename(self)
        return ("LUFactorization(%s)"):format(tostring(T))
    end
    base.AbstractBase(lu)

    terra lu:rows()
        return self.a:size(0)
    end

    terra lu:cols()
        return self.a:size(1)
    end

    terra lu:factorize()
        escape
            local impl = factorize:dispatch(&M, &P, Ts)
            emit quote return impl(self.a, self.p, self.tol) end
        end
    end

    terraform lu:solve(trans: B, x: &V) where {B: Bool, V: Vector}
        solve(trans, self.a, self.p, x)
    end

    terraform lu:apply(trans: B, a: T, x: &V1, b: T, y: &V2)
        where {B: Bool, V1: Vector, V2: Vector}
        self:solve(trans, x)
        y:scal(b)
        y:axpy(a, x)
    end

    assert(Factorization(lu))

    lu.staticmethods.new = terra(a: &M, p: &P, tol: Ts)
        err.assert(a:size(0) == a:size(1))
        err.assert(p:length() == a:size(0))
        return lu {a, p, tol}
    end

    return lu
end)

return {
    LUFactory = LUFactory,
}
