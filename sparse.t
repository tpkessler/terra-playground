-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local concepts = require("concepts")
local err = require("assert")
local base = require("base")
local matrix = require("matrix")

import "terraform"

local CSRMatrix = terralib.memoize(function(T, I)

    local Integral = concepts.Integral
    local Number = concepts.Number
    local Vector = concepts.Vector(T)
    local Matrix = concepts.Matrix(T)

    I = I or int64
    local ST = alloc.SmartBlock(T)
    local SI = alloc.SmartBlock(I)
    local struct csr {
        rows: I
        cols: I
        nnz: I
        data: ST
        col: SI
        rowptr: SI
    }
    csr.metamethods.__tostring = function(self)
        return ("CSRMatrix(%s, %s)"):format(tostring(T), tostring(I))
    end

    csr.eltype = T

    base.AbstractBase(csr)

    terra csr:rows()
        return self.rows
    end

    terra csr:cols()
        return self.cols
    end

    terraform csr:apply(trans: bool, alpha: T, x: &V1, beta: T, y: &V2)
        where {V1: Vector, V2: Vector}
        if beta == 0 then
            y:fill(0)
        else
            y:scal(beta)
        end
        if not trans then
            for i = 0, self.rows do
                var res = [T](0)
                for idx = self.rowptr(i), self.rowptr(i + 1) do
                    res = res + self.data(idx) * x:get(self.col(idx))
                end
                y:set(i, alpha * res + y:get(i))
            end
        else
            for i = 0, self.rows do
                for idx = self.rowptr(i), self.rowptr(i + 1) do
                    var j = self.col(idx)
                    var yold = y:get(j)
                    y:set(j, yold + alpha * self.data(idx) * x:get(i))
                end
            end
        end
    end
   
    terra csr:get(i: I, j: I)
        err.assert(i < self.rows and j < self.cols)
        for idx = self.rowptr(i), self.rowptr(i + 1) do
            if self.col(idx) == j then
                return self.data(idx)
            end
        end
        return [T](0)
    end

    local insert
    terraform insert(blk, k, x)
        blk:reallocate(blk:size() + 1)
        for i = k, blk:size() - 1 do
            blk(i + 1) = blk(i)
        end
        blk(k) = x
    end

    terra csr:set(i: I, j: I, x: T)
        err.assert(
            self.data:owns_resource()
            and self.col:owns_resource()
            and self.rowptr:owns_resource()
        )
        err.assert(i < self.rows and j < self.cols)
        var idx: I = self.rowptr(i)
        var is_new = true
        for k = self.rowptr(i), self.rowptr(i + 1) do
            var jref = self.col(k)
            if jref >= j then
                idx = k
                is_new = (jref ~= j)
                break
            end
        end
        if not is_new then
            self.data(idx) = x
        else
            insert(&self.data, idx, x)
            insert(&self.col, idx, j)
            for l = i + 1, self.rows + 1 do
                self.rowptr(l) = self.rowptr(l) + 1
            end
        end
    end

    local new
    terraform new(alloc, rows: N, cols: M) where {N: Integral, M: Integral}
        var a = csr {}
        a.rows = rows
        a.cols = cols
        a.data = alloc:allocate(sizeof(T), 1)
        a.data(0) = 0
        a.col = alloc:allocate(sizeof(I), 1)
        a.col(0) = 0
        a.rowptr = alloc:allocate(sizeof(I), rows + 1)
        for i = 0, rows + 1 do
            a.rowptr(i) = 0
        end
        return a
    end
    csr.staticmethods.new = new

    csr.staticmethods.frombuffer = (
        terra(rows: I, cols: I, nnz: I, data: &T, col: &I, rowptr: &I)
            var a = csr {}
            a.rows = rows
            a.cols = cols
            a.data = ST.frombuffer(nnz, data)
            a.col = SI.frombuffer(nnz, col)
            a.rowptr = SI.frombuffer(rows + 1, rowptr)
            return a
        end
    )

    matrix.MatrixBase(csr)
    assert(Matrix(csr))

    return csr
end)

return {
    CSRMatrix = CSRMatrix,
}
