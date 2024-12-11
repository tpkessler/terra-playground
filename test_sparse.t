-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local sparse = require("sparse")
local nfloat = require("nfloat")
local complex = require("complex")
local dvector = require("dvector")
local tmath = require("mathfuns")

local complexDouble = complex.complex(double)
local float256 = nfloat.FixedFloat(256)

import "terratest/terratest"

local tols = {
    -- [float] = `1e-7f,
    [double] = `1e-15,
    -- [float256] = `1e-30,
    -- [complexDouble] = `1e-14,
}

local DefaultAlloc = alloc.DefaultAllocator()
--[=[
for T, tol in pairs(tols) do
    local I = int32
    -- for _, I in pairs({int32, int64, uint32, uint64}) do
        local CSR = sparse.CSRMatrix(T, I)
        local Vec = dvector.DynamicVector(T)
        testenv(T, I) "Sparse CSR Matrix" do
            terracode
                var alloc: DefaultAlloc
                var n = 3
                var m = 4
                var a = CSR.new(&alloc, n, m)
            end

            -- testset "Dimensions" do
            --     test a:rows() == n
            --     test a:cols() == m
            -- end

            -- testset "Set and Get" do
            --     terracode
            --         var i = 1
            --         var j = 2
            --         var x: T = -2
            --         -- a:set(i, j, x)
            --         var y = a:get(i, j)
            --         -- a:set(i, j, -x)
            --         var z = a:get(i, j)
            --         -- a:set(j, i, 2 * x)
            --         var w = a:get(j, i)
            --     end
            --     -- test y == x
            --     -- test z == -x
            --     -- test w == 2 * x
            -- end

            -- testset "Frombuffer" do
            --     terracode
            --         var rows = 3
            --         var cols = 2
            --         var data = arrayof(T, 1, 2, 3, 4, 5, 6)
            --         var col = arrayof(I, 0, 1, 0, 1, 0, 1)
            --         var rowptr = arrayof(I, 0, 2, 4, 6)
            --         var b = CSR.frombuffer(
            --             rows, cols, rows * cols, &data[0], &col[0], &rowptr[0]
            --         )
            --     end

            --     test b:rows() == rows
            --     test b:cols() == cols
            --     for ii = 0, 2 do
            --         for jj = 0, 1 do
            --             -- test b:get(ii, jj) == data[cols * ii + jj]
            --         end
            --     end
            -- end

            testset "Apply" do
                terracode
                    var rows = 5
                    var c = CSR.new(&alloc, rows, rows)
                    -- for i = 0, rows do
                    --     c:set(i, i, 2)
                    -- end
                    -- for i = 1, rows do
                    --     c:set(i, i - 1, -1)
                    -- end
                    var xv = Vec.from(&alloc, 1, 2, 3, 4, 5)
                    var yv = Vec.ones_like(&alloc, &xv)
                    -- var yvref = Vec.from(&alloc, -1, -3, -5, -7, -9)
                    var yvref = Vec.from(&alloc, 2, 3, 4, 5, 6)
                    var alpha: T = 1
                    var beta: T = 0
                    -- c:apply(false, alpha, &xv, beta, &yv)
                end

                test c:rows() == 5
                test c:cols() == 5
                for ii = 0, 5 -1 do
                    -- test tmath.isapprox(yv(ii), yvref(ii), [tol])
                end
            end
        end
    -- end
end
--]=]

local stack = require("stack")
local Alloc = alloc.Allocator
local S = stack.DynamicStack(int32)
local struct A {
    data: S
}
local terra new(alloc: Alloc, cap: int32)
    var a: A
    a.data = S.new(alloc, cap)
end

terra main()
    var alloc: DefaultAlloc
    var cap = 10
    var a = new(&alloc, cap)
end
main()
