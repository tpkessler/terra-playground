-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local sparse = require("sparse")
local nfloat = require("nfloat")
local complex = require("complex")

local complexDouble = complex.complex(double)
local float256 = nfloat.FixedFloat(256)

import "terratest/terratest"

local Alloc = alloc.DefaultAllocator()
for _, T in pairs({float, double, float256, complexDouble}) do
    for _, I in pairs({int32, int64, uint32, uint64}) do
        local CSR = sparse.CSRMatrix(T, I)
        testenv(T) "Sparse CSR Matrix" do
            terracode
                var alloc: Alloc
                var n = 3
                var m = 4
                var a = CSR.new(&alloc, n, m)
            end

            testset "Dimensions" do
                test a:rows() == n
                test a:cols() == m
            end

            local io = terralib.includec("stdio.h")
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
                        -- print(i, j, type(i), type(j))
                        test b:get(ii, jj) == cols * ii + jj + 1
                    end
                end
            end
        end
    end
end
