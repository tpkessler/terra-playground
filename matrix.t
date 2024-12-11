-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local concepts = require("concepts")
local template = require("template")
local err = require("assert")

local Bool = concepts.Bool
local Integral = concepts.Integral
local Number = concepts.Number


local function MatrixBase(M)
    local T = M.eltype

    --operator concept
    local Vector = concepts.Vector(T)
    local Operator = concepts.Operator(T)
    local Matrix = concepts.Matrix(T)

    local function get(A, atrans, i, j)
        if atrans then
            if concepts.Complex(T) then
                return quote var x = [A]:get([j], [i]) in x:conj() end
            else
                return `[A]:get([j], [i])
            end
        else
            return `[A]:get([i], [j])
        end
    end
    
    terraform M:apply(trans : bool, alpha : T, x : &V, beta : T, y : &V) where {V :Vector}
        if trans then
            var ns = self:rows()
            var ms = self:cols()
            var nx = x:size()
            var ny = y:size()
            err.assert(ms == ny and ns == nx)
            for i = 0, ms do
                var res = [M.eltype](0)
                for j = 0, ns do
                    res = res + [get(self, true, i, j)] * x:get(j)
                end
                y:set(i, beta * y:get(i) + alpha * res)
            end
        else
            var ns = self:rows()
            var ms = self:cols()
            var nx = x:size()
            var ny = y:size()
            err.assert(ns == ny and ms == nx)
            for i = 0, ns do
                var res = [M.eltype](0)
                for j = 0, ms do
                    res = res + self:get(i, j) * x:get(j)
                end
                y:set(i, beta * y:get(i) + alpha * res)
            end
        end
    end

    --check if operator concept is implemented
    assert(Operator(M))
    
    terra M:fill(a : T)
        var rows = self:rows()
        var cols = self:cols()
        for i = 0, rows do
            for j = 0, cols do
                self:set(i, j, a)
            end
        end
    end

    terra M:clear()
        self:fill(0)
    end

    terraform M:copy(trans : bool, other : &M) where {M : Matrix}
        var ns = self:rows()
        var ms = self:cols()
        var no = other:rows()
        var mo = other:cols()
        if trans then
            err.assert(ns == mo and ms == no)
            for i = 0, ns do
                for j = 0, ms do
                    self:set(i, j, other:get(j, i))
                end
            end
        else
            err.assert(ns == no and ms == mo)
            for i = 0, ns do
                for j = 0, ms do
                    self:set(i, j, other:get(i, j))
                end
            end
        end
    end

    terraform M:swap(trans : bool, other : &M) where {M : Matrix}
        var ns = self:rows()
        var ms = self:cols()
        var no = other:rows()
        var mo = other:cols()
        if trans then
            err.assert(ns == mo and ms == no)
            for i = 0, ns do
                for j = 0, ms do
                    var s = self:get(i, j)
                    var o = other:get(j, i)
                    self:set(i, j, o)
                    other:set(j, i, s)
                end
            end
        else
            err.assert(ns == no and ms == mo)
            for i = 0, ns do
                for j = 0, ms do
                    var s = self:get(i, j)
                    var o = other:get(i, j)
                    self:set(i, j, o)
                    other:set(i, j, s)
                end
            end
        end
    end

    terra M:scal(a : T)
        var ns = self:rows()
        var ms = self:cols()
        for i = 0, ns do
            for j = 0, ms do
                self:set(i, j, a * self:get(i, j))
            end
        end
    end

    terraform M:axpy(a : T, trans : bool, other : &M) where {M : Matrix}
        var ns = self:rows()
        var ms = self:cols()
        var no = other:rows()
        var mo = other:cols()
        if trans then
            err.assert(ns == mo and ms == no)
            for i = 0, ns do
                for j = 0, ms do
                    self:set(i, j, self:get(i, j) + a * other:get(j, i))
                end
            end
        else
            err.assert(ns == no and ms == mo)
            for i = 0, ns do
                for j = 0, ms do
                    self:set(i, j, self:get(i, j) + a * other:get(i, j))
                end
            end
        end
    end

    terraform M:dot(trans : bool, other : &M) where {M : Matrix}
        var ns = self:rows()
        var ms = self:cols()
        var no = other:rows()
        var mo = other:cols()
        if trans then
            err.assert(ns == mo and ms == no)
            var sum = self:get(0, 0) * other:get(0, 0)
            for i = 0, ns do
                for j = 0, ms do
                    if i > 0 or j > 0 then
                        sum = sum + self:get(i, j) * other:get(j, i)
                    end
                end
            end
            return sum
        else
            err.assert(ns == no and ms == mo)
            var sum = self:get(0, 0) * other:get(0, 0)
            for i = 0, ns do
                for j = 0, ms do
                    if i > 0 or j > 0 then
                        sum = sum + self:get(i, j) * other:get(i, j)
                    end
                end
            end
            return sum
        end
    end
    
    local function kernel(C, beta, alpha, atrans, A, btrans, B)
        local dim = quote
            var d: uint64
            if atrans then
                d = [A]:rows()
            else
                d = [A]:cols()
            end
        in
            d
        end
        return quote
            for i = 0, [C]:rows() do
                for j = 0, [C]:cols() do
                    var sum = beta * [C]:get(i, j)
                    for k = 0, [dim] do
                        sum = sum + alpha * [get(A, atrans, i, k)]
                                          * [get(B, btrans, k, j)]
                    end
                    [C]:set(i, j, sum)
                end
            end
        end
    end
    
    terraform M:mul(beta : T, alpha : T, atrans : bool, a : &Mat, btrans : bool, b : &Mat) 
        where {Mat : Matrix}
        if atrans and btrans then
            err.assert(self:rows() == a:cols() and self:cols() == b:rows())
            err.assert(a:rows() == b:cols())
            [kernel(`self, `beta, `alpha, true, `a, true, `b)]
        elseif atrans and not btrans then
            err.assert(self:rows() == a:cols() and self:cols() == b:cols())
            err.assert(a:rows() == b:rows())
            [kernel(`self, `beta, `alpha, true, `a, false, `b)]
        elseif not atrans and btrans then
            err.assert(self:rows() == a:rows() and self:cols() == b:rows())
            err.assert(a:cols() == b:cols())
            [kernel(`self, `beta, `alpha, false, `a, true, `b)]
        else
            err.assert(self:rows() == a:rows() and self:cols() == b:cols())
            err.assert(a:cols() == b:rows())
            [kernel(`self, `beta, `alpha, false, `a, false, `b)]
        end
    end

    --check if the Matrix concept is satisfied
    assert(Matrix(M))
end

return {
    MatrixBase = MatrixBase,
}
