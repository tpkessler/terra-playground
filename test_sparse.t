-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local sparse = require("sparse")
local nfloat = require("nfloat")
local complex = require("complex")
local darray = require("darray")
local matrix = require("matrix")
local tmath = require("tmath")

local complexDouble = complex.complex(double)
local float256 = nfloat.FixedFloat(256)

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
        local Vec = darray.DynamicVector(T)
        local Mat = darray.DynamicMatrix(T)
        testenv(T, I) "Sparse CSR Matrix" do
            terracode
                var alloc: DefaultAlloc
                var n = 3
                var m = 4
                var a = CSR.new(&alloc, n, m)
            end

            testset "Dimensions" do
                test a:rows() == n
                test a:cols() == m
            end

            testset "Set and Get" do
                terracode
                    var i = 1
                    var j = 2
                    var x: T = -2
                    a:set(i, j, x)
                    var y = a:get(i, j)
                    a:set(i, j, -x)
                    var z = a:get(i, j)
                    a:set(j, i, 2 * x)
                    var w = a:get(j, i)
                end
                test y == x
                test z == -x
                test w == 2 * x
            end

            testset "Frombuffer" do
                terracode
                    var rows = 3
                    var cols = 2
                    var data = arrayof(T, 1, 2, 3, 4, 5, 6)
                    var col = arrayof(I, 0, 1, 0, 1, 0, 1)
                    var rowptr = arrayof(I, 0, 2, 4, 6)
                    var b = CSR.frombuffer(
                        rows, cols, rows * cols, &data[0], &col[0], &rowptr[0]
                    )
                end

                test b:rows() == rows
                test b:cols() == cols
                for ii = 0, 2 do
                    for jj = 0, 1 do
                        test b:get(ii, jj) == data[cols * ii + jj]
                    end
                end
            end

            testset "Apply" do
                terracode
                    var rows = 5
                    var c = CSR.new(&alloc, rows, rows)
                    for i = 0, rows do
                        c:set(i, i, 2)
                    end
                    for i = 1, rows do
                        c:set(i, i - 1, -1)
                    end
                    var xv = Vec.from(&alloc, {1, 2, 3, 4, 5})
                    var yv = Vec.ones(&alloc, 5)
                    var yvref = Vec.from(&alloc, {-1, -3, -5, -7, -9})
                    var alpha: T = -2
                    var beta: T = 3
                    matrix.gemv(alpha, &c, &xv, beta, &yv)
                end

                test c:rows() == 5
                test c:cols() == 5
                for ii = 0, 5 - 1 do
                    test tmath.isapprox(yv(ii), yvref(ii), [tol])
                end
            end

            testset "Mult" do
                terracode
                    var rows = 250
                    var cols = 200
                    var a = CSR.new(&alloc, rows, rows)
                    for i = 0, rows do
                        a:set(i, i, 3)
                    end
                    for i = 1, rows do
                        a:set(i, i - 1, -1)
                    end
                    for i = 0, rows - 1 do
                        a:set(i, i + 1, -1)
                    end
                    var b = Mat.new(&alloc, {rows, cols})
                    b:fill([T](2))
                    var c = Mat.new(&alloc, {rows, cols})
                    c:fill([T](3))
                    matrix.gemm([T](1), &a, &b, [T](-1), &c)
                end
                test tmath.isapprox(c(rows - 2, cols - 3), -3 + 2, [tol])
            end
        end
    end
end
