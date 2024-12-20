-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local concepts = require("concepts")
local err = require("assert")

local Integer = concepts.Integer
local Number = concepts.Number
local Stack = concepts.Stack
local Matrix = concepts.Matrix

--compute y[i] = alpha * A[i,j] * x[j] + beta * y[i]
local terraform gemv(alpha : T, A : &M, x : &V1, beta : T, y : &V2) 
        where {T : Number, M : Matrix(Number),  V1 : Stack(Number), V2 : Stack(Number)}
    var ns = A:rows()
    var ms = A:cols()
    var nx = x:length()
    var ny = y:length()
    err.assert(ns == ny and ms == nx)
    for i = 0, ns do
        var res = T(0)
        for j = 0, ms do
            res = res + self:get(i, j) * x:get(j)
        end
        y:set(i, beta * y:get(i) + alpha * res)
    end
end

--C[i,j] = alpha * A[i,k] * B[k,j] + beta * C[i,j]
local terraform gemm(alpha : T, A : &M1, B : &M2, beta : T, C : &M3)
        where {T : Number, M1 : Matrix(Number), M2 : Matrix(Number), M3 : Matrix(Number)}
    err.assert(A:size(1) == B:size(0), "ArgumentError: matrix dimensions in C = alpha*C + beta * A * B are not consistent.")
    err.assert(C:size(0) == A:size(0) and C:size(1) == B:size(1), "ArgumentError: matrix dimensions in C = alpha*C + beta * A * B are not consistent.")
    for i = 0, C:size(0) do
        for j = 0, C:size(1) do
            var sum = beta * C:get(i, j)
            for k = 0, A:size(1) do
                sum = sum + alpha * A:get(i, k) * B:get(k, j)
            end
            C:set(i, j, sum)
        end
    end
end

return {
    gemv = gemv,
    gemm = gemm
}
