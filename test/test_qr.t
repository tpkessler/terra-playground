-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest@v1/terratest"

local qr = require("qr")
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
             ["double"] = 1e-15,
             [tostring(float128)] = `[float128]("1e-30"),
             [tostring(float1024)] = `[float1024]("1e-300"),
            }

local T = double
local Vec = darray.DynamicVector(T)
local Mat = darray.DynamicMatrix(T)
local QRDense = qr.QRFactory(Mat, Vec)
local Alloc = alloc.DefaultAllocator()
local io = terralib.includec("stdio.h")

for _, Ts in pairs({float, double, float128, float1024}) do
    for _, is_complex in pairs({false, true}) do
        local T = is_complex and complex.complex(Ts) or Ts
        local unit = is_complex and T:unit() or 0
        local DMat = darray.DynamicMatrix(T)
        local DVec = darray.DynamicVector(T)
        local Alloc = alloc.DefaultAllocator()
        local Rand = random.LibC(float)
        local QRDense = qr.QRFactory(DMat, DVec)

        testenv(T) "QR factorization of random matrix" do
            local n = 41
            terracode
                var alloc: Alloc
                var rand = Rand.new(384905)
                var a = DMat.new(&alloc, {n, n})
                var x = DVec.new(&alloc, n)
                var y = DVec.zeros(&alloc, n)
                var yt = DVec.zeros(&alloc, n)
                for i = 0, n do
                    x(i) = rand:random_normal(0, 1) + [unit] * rand:random_normal(0, 1)
                    for j = 0, n do
                        a(i, j) = rand:random_normal(0, 1) + [unit] * rand:random_normal(0, 1)
                    end
                end
                matrix.gemv([T](1), &a, &x, [T](0), &y)
                matrix.gemv([T](1), a:transpose(), &x, [T](0), &yt)
                var u = DVec.new(&alloc, n)
                var tol: Ts = [ tol[tostring(Ts)] ]
                var qr = QRDense.new(&a, &u)
                qr:factorize()
                qr:solve(false, &y)
                qr:solve(true, &yt)
            end

            testset "Solve" do
                for i = 0, n - 1 do
                    test tmath.abs(y(i) - x(i)) < 1000 * tol * tmath.abs(x(i)) + tol
                end
            end

            testset "Solve transposed" do
                for i = 0, n - 1 do
                    test tmath.abs(yt(i) - x(i)) < 2000 * tol * tmath.abs(x(i)) + tol
                end
            end
        end
    end
end
