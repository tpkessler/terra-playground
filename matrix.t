-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local concepts = require("concepts")
local err = require("assert")


local function MatrixBase(M)
    
    local T = M.eltype
    
    terraform M:apply(alpha : S1, x : &V1, beta : S2, y : &V2) 
            where {S1 : Number, V1 : Vector, S2 : Number, V2 : Vector}
        var m, n = self:size(0), self:size(1)
        var nx = x:length()     --domain vector
        var ny = y:length()     --image vector
        err.assert(x:length() == n and y:length() == m)
        for i = 0, m do
            var res = T(0)
            for j = 0, n do
                res = res + self:get(i, j) * x:get(j)
            end
            y:set(i, beta * y:get(i) + alpha * res)
        end
    end

    assert(operator.Operator(M))
    operator.Operator:addimplementations{M}
    
    --self = beta * self + alpha * A * B
    terraform M:mul(beta : S1, alpha : S2, A : &M1, B : &M2) 
                where {S1 : Number, S2 : Number, M1 : Matrix, M2 : Matrix}
        err.assert(A:size(1) == B:size(0), "ArgumentError: matrix dimensions in C = a*C + b * A * B are not consistent.")
        err.assert(self:size(0) == A:size(0) and self:size(1) == B:size(1), "ArgumentError: matrix dimensions in C = a*C + b * A * B are not consistent.")
        var K = A:size(1)
        for i = 0, self:size(0) do
            for j = 0, self:size(1) do
                var sum = beta * self:get(i, j)
                for k = 0, K do
                    sum = sum + alpha * A:get(i, k) * B:get(k, j)
                end
                self:set(i, j, sum)
            end
        end
    end

    assert(Matrix(M))
    Matrix:addimplementations{M}
end

return {
    Matrix = concepts.Matrix,
    MatrixBase = MatrixBase,
}
