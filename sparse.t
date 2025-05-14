-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local stack = require("stack")
local concepts = require("concepts")
local err = require("assert")
local base = require("base")
local matrix = require("matrix")
local packed = require("packed")
local simd = require("simd")
local lambda = require("lambda")
local thread = require("thread")
local range = require("range")
local parametrized = require("parametrized")

import "terraform"

local CSRMatrix = parametrized.type(function(T, I)

    local Integral = concepts.Integral
    local Number = concepts.Number
    local Vector = concepts.Vector(T)
    local Matrix = concepts.Matrix(T)

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
    csr.traits.eltype = T

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
        -- Initialize the column index with something outside of the index
        -- range to avoid index collisions.
        var jref: I = -1
        while idx < self.rowptr(i + 1) do
            jref = self.col(idx)
            -- Within each row we sort the indices in increasing order.
            -- Hence, if the reference index jref is not smaller than j
            -- we found the right global index idx to insert our entry in the
            -- col and data stacks.
            if jref >= j then
                break
            else
                idx = idx + 1
            end
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
    assert(Matrix(csr))

    terra csr:nnz()
        return self.data:size()
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

    local Primitive = concepts.Primitive
    if Primitive(T) then
        -- Inspired by the GPU implementation
        -- https://gpuopen.com/learn/amd-lab-notes/amd-lab-notes-spmv-docs-spmv_part1/
        local VecApply = parametrized.type(function(N)
            local SIMD = simd.VectorFactory(T, N)
            local terraform vecapply(
                self: &csr,
                trans: bool,
                alpha: T,
                x: &V1,
                beta: T,
                y: &V2
            ) where {V1: Vector, V2: Vector}
                if beta == 0 then
                    y:fill(0)
                else
                    y:scal(beta)
                end
                if not trans then
                    for i = 0, self.rows do
                        var first = self.rowptr(i)
                        var last = self.rowptr(i + 1)
                        var len = last - first
                        var veclen = len - len % N
                        var vecres: SIMD = [T](0)
                        for idx = first, first + veclen, N do
                            var avec: SIMD = &self.data(idx)
                            var xvec: SIMD = (
                                escape
                                    local arg = terralib.newlist()
                                    for j = 0, N - 1 do
                                        arg:insert(`x:get(self.col(idx + j)))
                                    end
                                    emit `vectorof(T, [arg])
                                end
                            )
                            vecres = vecres + avec * xvec
                        end
                        var res = vecres:hsum()
                        for idx = first + veclen, first + len do
                            res = res + self.data(idx) * x:get(self.col(idx))
                        end
                        y:set(i, y:get(i) + alpha * res)
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
            return vecapply
        end)
        local MAX_POWER = 5
        local MAX_VECLEN = 2 ^ MAX_POWER
        terraform csr:apply(trans: bool, alpha: T, x: &V1, beta: T, y: &V2)
            where {V1: Vector, V2: Vector}
            var nnzrow = self.data:size() / self:rows()
            var veclen = 1
            while veclen < nnzrow do
                veclen = 2 * veclen
            end
            veclen = terralib.select(veclen > MAX_VECLEN, MAX_VECLEN, veclen)
            escape
                for i = 1, MAX_POWER do
                    local N = 2 ^ i
                    emit quote
                        if veclen <= N then
                            return (
                                [VecApply(N)](self, trans, alpha, x, beta, y)
                            )
                        end
                    end
                end
            end
        end
    end


    -- Rosko: Row Skipping Outer Products for Sparse Matrix Multiplication Kernels
    -- https://arxiv.org/abs/2307.03930
    local BLASFloat = concepts.BLASFloat
    local SparsePacked = concepts.SparsePacked
    local DensePacked = concepts.DensePacked
    local terraform blocked_outer_product(
        alpha: T, a: &A, b: &B, c: &C
    ) where {
            A: SparsePacked(BLASFloat),
            B: DensePacked(BLASFloat),
            C: DensePacked(BLASFloat)
        }
        escape
            assert(A.traits.Rows == C.traits.Rows)
            assert(A.traits.Cols == B.traits.Rows)
            assert(B.traits.Cols == C.traits.Cols)
        end
        var cv: simd.VectorFactory(T, A.traits.Cols)[A.traits.Rows]
        for m = 0, [A.traits.Rows] do
            cv[m] = &c.A[ m * [C.traits.Cols] ]
        end
        var Ap = &a.Ap[0]
        var loc = &a.loc[0]
        for k = 0, [A.traits.Cols] do
            if a.nnz[k] == 0 then
                break
            end
            var bv: simd.VectorFactory(T, A.traits.Cols) = (
                &b.A[ a.col[k] * [B.traits.Cols] ]
            )
            for m = 0, a.nnz[k] do
                var av: simd.VectorFactory(T, A.traits.Cols) = alpha * @Ap
                Ap = Ap + 1
                cv[@loc] = cv[@loc] + av * bv
                loc = loc + 1
            end
        end
        for m = 0, [A.traits.Rows] do
            cv[m]:store(&c.A[ m * [C.traits.Cols] ])
        end
    end

    local Number = concepts.Number
    local terraform blocked_outer_product(
        alpha: T, a: &A, b: &B, c: &C
    ) where {
            A: SparsePacked(Number),
            B: DensePacked(Number),
            C: DensePacked(Number)
        }
        escape
            assert(A.traits.Rows == C.traits.Rows)
            assert(A.traits.Cols == B.traits.Rows)
            assert(B.traits.Cols == C.traits.Cols)
        end
        var cv: (&T)[C.traits.Rows]
        for m = 0, [C.traits.Rows] do
            cv[m] = &c.A[ m * [C.traits.Cols] ]
        end
        var Ap = &a.Ap[0]
        var loc = &a.loc[0]
        for k = 0, [A.traits.Cols] do
            if a.nnz[k] == 0 then
                break
            end
            var bv = &b.A[ a.col[k] * [B.traits.Cols] ]
            for m = 0, a.nnz[k] do
                var av = alpha * @Ap
                for n = 0, [C.traits.Cols] do
                    cv[@loc][n] = cv[@loc][n] + av * bv[n]
                end
                Ap = Ap + 1
                loc = loc + 1
            end
        end
    end

    local ARows = math.floor(128 * sizeof(double) / sizeof(T))
    local ACols = math.floor(128 * sizeof(double) / sizeof(T))
    local BCols = math.floor(128 * sizeof(double) / sizeof(T))
    local Matrix = concepts.Matrix(T)
    -- TODO Implement missing cases
    terraform matrix.gemm(
        alpha: T,
        A: &csr,
        B: &M1,
        beta: T,
        C: &M2
    ) where {M1: Matrix, M2: Matrix}
        var na = A:rows()
        var ma = A:cols()
        var nb = B:rows()
        var mb = B:cols()
        var nc = C:rows()
        var mc = C:cols()
        err.assert(na == nc)
        err.assert(ma == nb)
        err.assert(mb == mc)
        var nblocka: I = (na + ARows - 1) / ARows
        var mblocka: I = (ma + ACols - 1) / ACols
        var mblockb: I = (mb + BCols - 1) / BCols

        if beta == 0 then
            C:fill(0)
        else
            C:scal(beta)
        end

        -- CAKE: matrix multiplication using constant-bandwidth blocks
        -- https://dl.acm.org/doi/abs/10.1145/3458817.3476166
        var rn = range.product(
            [range.Unitrange(I)].new(0, mblockb),
            [range.Unitrange(I)].new(0, nblocka)
        )
        var go = lambda.new(
            [
                terra(
                    it: {I, I},
                    alpha: alpha.type,
                    A: A.type,
                    B: B.type,
                    beta: beta.type,
                    C: C.type,
                    mblocka: mblocka.type
                )
                    var jdx, idx = it
                    var ap: packed.SparsePackedFactory(T, I, ARows, ACols)
                    var bp: packed.DensePackedFactory(T, ACols, BCols)
                    var cp: packed.DensePackedFactory(T, ARows, BCols)

                    cp:pack(C, idx * ARows, jdx * BCols)
                    for k = 0, mblocka do
                        var kdx = k
                        ap:pack(A, idx * ARows, kdx * ACols)
                        bp:pack(B, kdx * ACols, jdx * BCols)
                        blocked_outer_product(alpha, &ap, &bp, &cp)
                    end
                    cp:unpack(C, idx * ARows, jdx * BCols)
                end
            ],
            {alpha = alpha, A = A, B = B, beta = beta, C = C, mblocka = mblocka}
        )
        -- HACK: Use default allocator as we cannot access the allocator
        -- for the sparse matrix.
        var allocator: alloc.DefaultAllocator()
        thread.parfor(&allocator, rn, go)
    end

    local Alloc = alloc.Allocator
    csr.staticmethods.new = terra(alloc: Alloc, rows: I, cols: I)
        var a: csr
        a.rows = rows
        a.cols = cols
        var cap = rows -- one entry per row
        a.data = ST.new(alloc, cap)
        a.col = SI.new(alloc, cap)
        a.rowptr = SI.new(alloc, rows + 1)
        for i = 0, rows + 1 do
            a.rowptr:push(0)
        end
        return a
    end

    csr.staticmethods.frombuffer = (
        terra(rows: I, cols: I, nnz: I, data: &T, col: &I, rowptr: &I)
            var a: csr
            a.rows = rows
            a.cols = cols
            a.data = ST.frombuffer(nnz, data)
            a.col = SI.frombuffer(nnz, col)
            a.rowptr = SI.frombuffer(rows + 1, rowptr)
            return a
        end
    )

    return csr
end)

return {
    CSRMatrix = CSRMatrix,
}
