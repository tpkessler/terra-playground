-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local packed = require("packed")
local alloc = require("alloc")
local sparse = require("sparse")
local nfloat = require("nfloat")
local complex = require("complex")

local float256 = nfloat.FixedFloat(256)
local complexDouble = complex.complex(double)

import "terratest/terratest"

local tols = {
    [float] = `1e-7f,
    [double] = `1e-15,
    [float256] = `1e-30,
    [complexDouble] = `1e-14,
}

local DefaultAlloc = alloc.DefaultAllocator()
for T, tol in pairs(tols) do
    for _, I in pairs({int32, int64, uint32, uint64}) do
        local CSR = sparse.CSRMatrix(T, I)
        testenv(T, I) "Sparse packed" do
            terracode
                var alloc: DefaultAlloc
            end

            testset "Densely populated" do
                terracode
                    var rows = 2
                    var a = CSR.new(&alloc, rows, rows)
                    a:set(0, 0, 1)
                    a:set(0, 1, 2)
                    a:set(1, 0, 3)
                    a:set(1, 1, 4)
                    var ap: packed.SparsePackedFactory(T, I, 32, 32)
                    ap:pack(&a, 0, 0)
                end
                test ap.Ap[0] == 1
                test ap.Ap[1] == 3
                test ap.Ap[2] == 2
                test ap.Ap[3] == 4
                ---
                test ap.loc[0] == 0
                test ap.loc[1] == 1
                test ap.loc[2] == 0
                test ap.loc[3] == 1
                ---
                test ap.col[0] == 0
                test ap.col[1] == 1
                ---
                test ap.nnz[0] == 2
                test ap.nnz[1] == 2
            end

            testset "Full sparse" do
                terracode
                    var rows = 5
                    var a = CSR.new(&alloc, rows, rows)
                    for i = 1, rows - 1 do
                        a:set(i, i, i + 1)
                        if i ~= rows / 2 then
                            a:set(i, rows - i - 1, -i - 1)
                        end
                    end
                    var ap: packed.SparsePackedFactory(T, I, 32, 32)
                    ap:pack(&a, 0, 0)
                end
                test ap.Ap[0] == 2
                test ap.Ap[1] == -4
                test ap.Ap[2] == 3
                test ap.Ap[3] == -2
                test ap.Ap[4] == 4
                ---
                test ap.loc[0] == 1
                test ap.loc[1] == 3
                test ap.loc[2] == 2
                test ap.loc[3] == 1
                test ap.loc[4] == 3
                ---
                test ap.col[0] == 1
                test ap.col[1] == 2
                test ap.col[2] == 3
                ---
                test ap.nnz[0] == 2
                test ap.nnz[1] == 1
                test ap.nnz[2] == 2
            end

            testset "Sparse with offset" do
                terracode
                    var rows = 5
                    var a = CSR.new(&alloc, rows, rows)
                    for i = 1, rows - 1 do
                        a:set(i, i, i + 1)
                        if i ~= rows / 2 then
                            a:set(i, rows - i - 1, -i - 1)
                        end
                    end
                    var ap: packed.SparsePackedFactory(T, I, 32, 32)
                    ap:pack(&a, 1, 1)
                end
                test ap.Ap[0] == 2
                test ap.Ap[1] == -4
                test ap.Ap[2] == 3
                test ap.Ap[3] == -2
                test ap.Ap[4] == 4
                ---
                test ap.loc[0] == 0
                test ap.loc[1] == 2
                test ap.loc[2] == 1
                test ap.loc[3] == 0
                test ap.loc[4] == 2
                ---
                test ap.col[0] == 0
                test ap.col[1] == 1
                test ap.col[2] == 2
                ---
                test ap.nnz[0] == 2
                test ap.nnz[1] == 1
                test ap.nnz[2] == 2
            end
        end
    end
end
