-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

local cho = require("cholesky")
local alloc = require("alloc")
local random = require("random")
local complex = require("complex")
local nfloat = require("nfloat")
local darray = require("darray")
local matrix = require("matrix")
local tmath = require("tmath")

local float128 = nfloat.FixedFloat(128)
local float1024 = nfloat.FixedFloat(1024)
local tol = {["float"] = 1e-6,
             ["double"] = 1e-14,
             [tostring(float128)] = `[float128](1e-30),
             [tostring(float1024)] = `[float1024](1e-100),
            }

local io = terralib.includec("stdio.h")
for _, Ts in pairs({float, double, float128, float1024}) do
    for _, is_complex in pairs({false, true}) do
        local T = is_complex and complex.complex(Ts) or Ts
        local unit = is_complex and T:unit() or 0 
        local DMat = darray.DynamicMatrix(T)
        local DVec = darray.DynamicVector(T)
        local Alloc = alloc.DefaultAllocator(Ts)
        local Rand = random.LibC(float)
        local CholeskyDense = cho.CholeskyFactory(DMat)

        testenv(T) "Cholesky factorization for small matrix" do
            terracode
                var alloc: Alloc
                var a = DMat.from(&alloc, {{2, -1}, {-1, 2}})
                var tol: Ts = [ tol[tostring(Ts)] ]
                var cho = CholeskyDense.new(&a, tol)
                var x = DVec.from(&alloc, {2, 1})
                var xt = DVec.from(&alloc, {-1, 4})
                cho:factorize()
                cho:solve(false, &x)
                cho:solve(true, &xt)
            end

                testset "Factorize" do
                    test tmath.abs(a(0, 0) - tmath.sqrt([Ts](2))) < 10 * tol
                    test tmath.abs(a(1, 1) - tmath.sqrt([Ts](3) / 2)) < 10 * tol
                    test tmath.abs(a(1, 0) + tmath.sqrt([Ts](1) / 2)) < 10 * tol
                end

            testset "Solve" do
                test tmath.abs(x(0) - [T](5) / 3) < 10 * tol
                test tmath.abs(x(1) - [T](4) / 3) < 10 * tol
            end

            testset "Solve transposed" do
                test tmath.abs(xt(0) - [T](2) / 3) < 10 * tol
                test tmath.abs(xt(1) - [T](7) / 3) < 10 * tol
            end
        end

        testenv(T) "LU factorization for random matrix" do
            local n = 41
            terracode
                var alloc: Alloc
                var rand = Rand.new(2359586)
                var a = DMat.zeros(&alloc, {n, n})
                var b = DMat.zeros(&alloc, {n, n})
                var x = DVec.new(&alloc, n)
                var y = DVec.zeros(&alloc, n)
                var yt = DVec.zeros(&alloc, n)
                for i = 0, n do
                    x(i) = rand:random_normal(0, 1) + [unit] * rand:random_normal(0, 1)
                    for j = 0, n do
                        b(i, j) = rand:random_normal(0, 1) + [unit] * rand:random_normal(0, 1)
                    end
                end
                matrix.gemm([T](1), &b, b:transpose(), [T](0), &a)
                matrix.gemv([T](1), &a, &x, [T](0), &y)
                matrix.gemv([T](1), a:transpose(), &x, [T](0), &yt)
                var tol: Ts = [ tol[tostring(Ts)] ]
                var cho = CholeskyDense.new(&a, tol)
                cho:factorize()
                cho:solve(false, &y)
                cho:solve(true, &yt)
            end

            testset "Solve" do
                for i = 0, n - 1 do
                    test tmath.abs(y(i) - x(i)) < 20000 * tol * tmath.abs(x(i)) + tol
                end
            end

            testset "Solve transposed" do
                for i = 0, n - 1 do
                    test tmath.abs(yt(i) - x(i)) < 20000 * tol * tmath.abs(x(i)) + tol
                end
            end
        end
    end
end
