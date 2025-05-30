-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local blas = require("blas")
local concepts = require("concepts")
local complex = require("complex")
local C = terralib.includecstring[[
    #include <stdio.h>
]]
local tmath = require("tmath")
local complexFloat = complex.complex(float)
local complexDouble = complex.complex(double)

local types = {
	["s"] = float,
	["d"] = double,
	["c"] = complexFloat,
	["z"] = complexDouble}

local unit = {
	["s"] = `float(0),
	["d"] = `double(0),
	["c"] = `[complexFloat:unit()],
	["z"] = `[complexDouble:unit()]}

import "terratest"

for prefix, T in pairs(types) do
	local I = unit[prefix]
	testenv(T) "BLAS level 1" do
        testset "swap scalar" do
            terracode
                var x = T(1)
                var y = T(2)
                blas.swap(1, &x, 1, &y, 1)
            end
            test x == T(2)
            test y == T(1)
        end -- testset

        testset "swap vectors" do
            local n = 4
            local incx = 3
            local incy = 2
            terracode
                var x: T[n * incx]
                var y: T[n * incy]
                var xold: T[n * incx]
                var yold: T[n * incy]
                for i = 0, n do
                    x[i * incx] = T(i) + I * T(n - i)
                    xold[i * incx] = x[i * incx]
                    y[i * incy] = T(n - i) + I * T(i)
                    yold[i * incy] = y[i * incy]
                end
                blas.swap(n, &x[0], incx, &y[0], incy)
            end

            for i = 0, n - 1 do
                test x[i * incx] == yold[i * incy]
                test y[i * incy] == xold[i * incx]
            end
        end -- testset swap

        testset "scal scalar" do
            terracode
                var x = T(2)
                var xold = x
                var a = T(6)
                blas.scal(1, a, &x, 1)
            end
            test x == xold * a
        end --testset scal

        testset "scal vector" do
            local n = 4
            local incx = 3
            terracode
                var x: T[n * incx]
                var xold: T[n * incx]
                var a = T(5) + I * T(2)
                for i = 0, n do
                    x[i * incx] = T(i) + I * T(i * i)
                    xold[i * incx] = x[i * incx]
                end
                blas.scal(n, a, &x[0], incx)
            end

            for i = 0, n - 1 do
                test x[i * incx] == a * xold[i * incx]
            end
        end -- testset scal

        testset "copy scalar" do
            terracode
                var x = T(3)
                var y = T(1)
                blas.copy(1, &x, 1, &y, 1)
            end

            test x == y
        end -- testset copy

        testset "copy vector" do
            local n = 4
            local incx = 3
            local incy = 2
            terracode
                var x: T[n * incx]
                var y: T[n * incy]

                for i = 0, n do
                    x[i * incx] = T(i) + I * T(n * n - i + 1)
                end
                blas.copy(n, &x[0], incx, &y[0], incy)
            end

            for i = 0, n - 1 do
                test y[i * incy] == x[i * incx]
            end
        end -- testset copy

        testset "axpy scalar" do
            terracode
                var a = T(2)
                var x = T(2)
                var y = T(3)
                var yold = y
                blas.axpy(1, a, &x, 1, &y, 1)
            end

            test y == a * x + yold
        end -- testset axpy

        testset "axpy vectors" do
            local n = 4
            local incx = 3
            local incy = 2
            terracode
                var a = T(2) + I * T(-3)
                var x: T[n * incx]
                var y: T[n * incy]
                var yold: T[n * incy]

                for i = 0, n do
                    x[i * incx] = T(i) + I * T(-2 * n - i)
                    y[i * incy] = T(n - i) + I * T(3 * i)
                    yold[i * incy] = y[i * incy]
                end

                blas.axpy(n, a, &x[0], incx, &y[0], incy)
            end

            for i = 0, n - 1 do
                test y[i * incy] == a * x[i * incx] + yold[i * incy]
            end
        end -- testenv axpy

        testset "dot vectors" do
            local n = 4
            local incx = 3
            local incy = 2
            terracode
                var x: T[n * incx]
				var xconj: T[n * incx]
                var y: T[n * incy]

                for i = 0, n do
                    x[i * incx] = T(i) + I * T(i * i - n)
                    xconj[i * incx] = T(i) - I * T(i * i - n)
                    y[i * incy] = T(n - i) + I * T(-n - i)
                end
                var num = blas.dot(n, &x[0], incx, &y[0], incy)
                var ref = T(0)
                for i = 0, n do
                    ref = ref + xconj[i * incx] * y[i * incy]
                end
            end

            test ref == num
        end --testset dot

        testset "norm scalar" do
            local nrm = 3
            if not T:isfloat() then
                nrm = nrm + 2
            end
            terracode
                var x = 3 + 4 * I
                var xconj = 3 - 4 * I

                var num = blas.nrm2(1, &x, 1)
            end

            test num == nrm

        end --testset norm

        testset "norm vectors" do
            local n = 4
            local incx = 3
            local Ts = concepts.Complex(T) and T.traits.eltype or T
            terracode
                var x: T[n * incx]
                var xre: Ts[n * incx]
                var xim: Ts[n * incx]
                
                for i = 0, n do
                    xre[i * incx] = i
                    xim[i * incx] = n - i
                    x[i * incx] = xre[i * incx] + I * xim[i * incx] 
                end

                var num: Ts = blas.nrm2(n, &x[0], incx)

                var ref: Ts = 0
                for i = 0, n do
                    ref = ref + xre[i * incx] * xre[i * incx]
                end
                escape
                    if concepts.Complex(T) then
                        emit quote
                            for i = 0, n do
                                ref = ref + xim[i * incx] * xim[i * incx]
                            end
                        end --quote
                    end --if
                end --escape

                ref = tmath.sqrt(ref)
            end
                
            test tmath.isapprox(num, ref, 100 * [Ts:eps()])
            
        end

        testset "L1 norm" do
            local n = 5
            local incx = 2

            terracode
                var x: T[n * incx]
                for i = 0, n do
                    x[incx * i] = terralib.select(i % 2 == 0, T(i), T(-i))
                end
                
                var num = blas.asum(n, x, incx)
                var ref = n * (n - 1) / 2
            end

            test num == ref

        end

        testset "L infinity norm" do
            local n = 5
            local incx = 2

            terracode
                var x: T[n * incx]
                for i = 0, n do
                    x[incx * i] = terralib.select(i % 2 == 0, T(i), T(-i))
                end
                
                var num = blas.iamax(n, x, incx)
                var ref = n - 1
            end

            test num == ref

        end
    end -- testenv BLAS level 1

    testenv(T) "BLAS level 2" do
        testset "matrix-vector multiplication" do
            terracode
                var a = arrayof(T, 1, 2, 3, 4)
                var x = arrayof(T, 1, 1)
                var y: T[2]
                var yref = arrayof(T, 3, 7)

                var alpha = T(1)
                var beta = T(0)

                blas.gemv(blas.RowMajor, blas.NoTrans, 2, 2, alpha, &a[0], 2,
                          &x[0], 1, beta, &y[0], 1)
            end

            for i = 0, 1 do
                test y[i] == yref[i]
            end
        end
    end
   
    testenv(T) "BLAS level 3" do
        testset "triangular solve" do
            terracode
                var a = arrayof(T, 1, 2, 0, 3)
                var x = arrayof(T, 1, 2)
                var y = arrayof(T, 0, 0)

                var alpha = T(1)
                var beta = T(0)

                blas.gemv(blas.RowMajor, blas.NoTrans, 2, 2, alpha, &a[0], 2,
                          &x[0], 1, beta, &y[0], 1)

                blas.trsv(blas.RowMajor, blas.Upper, blas.NoTrans, blas.NonUnit,
                          2, &a[0], 2, &y[0], 1)
            end

            for i = 0, 1 do
                test y[i] == x[i]
            end
        end

        testset "matrix-matrix multiplication" do
            terracode
                var a = arrayof(T, 1, 2, 3, 4)
                var b = arrayof(T, 0, 0, 0, 0)
                var bref = arrayof(T, 5, 11, 11, 25)

                var alpha = T(1)
                var beta = T(0)

                blas.gemm(blas.RowMajor, blas.NoTrans, blas.Trans, 2, 2, 2, alpha,
                          &a[0], 2, &a[0], 2, beta, &b[0], 2)
            end

            for i = 0, 3 do
                test b[i] == bref[i]
            end
        end
    end
end -- for
