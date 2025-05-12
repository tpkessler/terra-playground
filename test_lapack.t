-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local lapack = require("lapack")
local blas = require("blas")
local complex = require("complex")
local io = terralib.includec("stdio.h")
local math = terralib.includec("math.h")

local complexFloat = complex.complex(float)
local complexDouble = complex.complex(double)

local types = {
    ["s"] = float,
    ["d"] = double,
    ["c"] = complexFloat,
    ["z"] = complexDouble,
}

local unit = {
    ["s"] = `float(0),
    ["d"] = `double(0),
    ["c"] = `[complexFloat:unit()],
    ["z"] = `[complexDouble:unit()],
}

local tol = {
    ["s"] = 1e-5,
    ["d"] = 1e-10,
    ["c"] = 1e-4,
    ["z"] = 1e-9,
}
local atol = 1e-14

import "terratest/terratest"

local abs = terralib.overloadedfunction("abs", {
    math.fabsf, math.fabs,
    terra(x: complexFloat) return x:norm() end,
    terra(x: complexDouble) return x:norm() end,
})

local function isclose(T)
    local terra impl(x: T, y: T, rtol: double, atol: double)
        return abs(x - y) < rtol * abs(x) + atol
    end

    return impl
end


for prefix, T in pairs(types) do
    local I = unit[prefix]
    local isclose = isclose(T)
    local rtol = tol[prefix]
    testenv(T) "LU decomposition" do
        local n = 2
        terracode
            var ld = n
            var a = arrayof(T, 1, 2, 3, 4)
            var x = arrayof(T, 1, 2)
            var y = arrayof(T, 0, 0)
            var alpha = T(1)
            var beta = T(0)
            var perm: int32[2]
            blas.gemv(blas.RowMajor, blas.NoTrans, n, n, alpha, &a[0], ld,
                      &x[0], 1, beta, &y[0], 1)
            var info = lapack.getrf(lapack.ROW_MAJOR, n, n, &a[0], ld, &perm[0])
        end

        testset "Factorization step" do
            test info == 0
        end

        testset "Solver step" do
            terracode
                info = lapack.getrs(lapack.ROW_MAJOR, @'N', n, 1, &a[0], ld,
                                    &perm[0], &y[0], 1)
            end

            test info == 0
            for i = 0, n - 1 do
                test isclose(x[i], y[i], rtol, atol)
            end
        end
    end -- LU

    testenv(T) "Cholesky decomposition" do
        local n = 2
        terracode
            var ld = n
            var b = arrayof(T, 1, 2, 3, 4)
            var x = arrayof(T, 1, 2)
            var y = arrayof(T, 0, 0)
            var a = arrayof(T, 0, 0, 0, 0)
            var alpha = T(1)
            var beta = T(0)
            blas.gemm(blas.RowMajor, blas.NoTrans, blas.Trans, n, n, n,
                      alpha, &b[0], ld, &b[0], ld, beta, &a[0], ld)
            blas.gemv(blas.RowMajor, blas.NoTrans, n, n, alpha, &a[0], ld,
                      &x[0], 1, beta, &y[0], 1)
            var info = lapack.potrf(lapack.ROW_MAJOR, @'L', n, &a[0], ld)
        end

        testset "Factorization step" do
            test info == 0
        end

        testset "Solver step" do
            terracode
                info = lapack.potrs(lapack.ROW_MAJOR, @'L', n, 1, &a[0], ld,
                                    &y[0], 1)
            end

            test info == 0
            for i = 0, n - 1 do
                test isclose(x[i], y[i], rtol, atol)
            end
        end
    end -- Cholesky

    testenv(T) "LDL decomposition" do
        local n = 2
        terracode
            var ld = n
            var a = arrayof(T, 1, 2, 2, 3)
            var x = arrayof(T, 1, 2)
            var y = arrayof(T, 0, 0)
            var alpha = T(1)
            var beta = T(0)
            blas.gemv(blas.RowMajor, blas.NoTrans, n, n, alpha, &a[0], ld,
                      &x[0], 1, beta, &y[0], 1)
            var perm: int32[n]
            var info = lapack.sytrf(lapack.ROW_MAJOR, @'L', n, &a[0], ld, &perm[0])
        end

        testset "Factorization step" do
            test info == 0
        end

        testset "Solver step" do
            terracode
                info = lapack.sytrs(lapack.ROW_MAJOR, @'L', n, 1, &a[0], ld,
                                    &perm[0], &y[0], 1)
            end

            test info == 0
            for i = 0, n - 1 do
                test isclose(x[i], y[i], rtol, atol)
            end
        end

    end -- LDL
end -- for type
