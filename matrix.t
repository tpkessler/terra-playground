-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local concepts = require("concepts")
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
            y:set(i, beta * y:get(i) + alpha * res)
        end
    end

    --check if operator concept is implemented
    assert(Operator(M))

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
