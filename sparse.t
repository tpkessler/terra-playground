-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local stack = require("stack")
local concepts = require("concepts")
local err = require("assert")
local base = require("base")
local vecbase = require("vector")
local matrix = require("matrix")

import "terraform"

local CSRMatrix = terralib.memoize(function(T, I)
    I = I or int64
    local ST = stack.DynamicStack(T)
    local SI = stack.DynamicStack(I)
    local struct csr {
        rows: I
        cols: I
        data: ST
        col: SI
        rowptr: SI
    }
    csr.metamethods.__typename = function(self)
        return ("CSRMatrix(%s, %s)"):format(tostring(T), tostring(I))
    end
    base.AbstractBase(csr)

    terra csr:rows()
        return self.rows
    end

    terra csr:cols()
        return self.cols
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

    terra csr:set(i: I, j: I, x: T)
        err.assert(i < self.rows and j < self.cols)
        var idx = self.rowptr(i)
        var jref: I = 0
        var is_new = true
        while idx < self.rowptr(i + 1) and jref < j do
            jref = self.col(idx)
            idx = idx + 1            
        end
        if jref == j then
            self.data(idx) = x
        else
            self.data:insert(idx, x)
            self.col:insert(idx, j)
            for l = i + 1, self.rows + 1 do
                self.rowptr(l) = self.rowptr(l) + 1
            end
        end
    end

    matrix.MatrixBase(csr)
    assert(matrix.Matrix(csr))

    terra csr:nnz()
        return self.data:size()
    end

    local Number = concepts.Number
    local Vector = vecbase.Vector
    terraform csr:apply(trans: bool, alpha: A, x: &V1, beta: B, y: &V2)
        where {A: Number, V1: Vector, B: Number, V2: Vector}
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

    local Alloc = alloc.Allocator
    local io = terralib.includec("stdio.h")
    csr.staticmethods.new = terra(alloc: Alloc, rows: I, cols: I)
        io.printf("New struct\n")
        var a = csr {}
        a.rows = rows
        a.cols = cols
        var cap = rows  -- one entry per row
        -- a.data = ST.new(alloc, cap)
        -- a. col = SI.new(alloc, cap)
        io.printf("Getting new rowptr\n")
        a.rowptr = SI.new(alloc, rows + 1)
        for i = 0, rows + 1 do
            -- a.rowptr:push(0)
        end
        return a
    end

    csr.staticmethods.frombuffer = (
        terra(rows: I, cols: I, nnz: I, data: &T, col: &I, rowptr: &I)
            var a = csr {}
            a.rows = rows
            a.cols = cols
            -- a.data = ST.frombuffer(nnz, data)
            -- a.col = SI.frombuffer(nnz, col)
            -- a.rowptr = SI.frombuffer(rows + 1, rowptr)
            return a
        end
    )

    return csr
end)

return {
    CSRMatrix = CSRMatrix,
}
