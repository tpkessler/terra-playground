-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest@v1/terratest"

local dual = require("dual")
local lambda = require("lambda")
local tmath = require("tmath")

for T, tol in pairs({[float] = `1e-6f, [double] = `1e-14}) do
    testenv(T) "Dual Number" do
        local Td = dual.DualNumber(T)
        testset "Init" do
            terracode
                var a = 14
                var b = 51
                var x = Td {a, b}
            end
            test x.val == a
            test x.tng == b
        end

        testset "Cast" do
            terracode
                var a = -124
                var x: Td = a
            end
            test x.val == a
            test x.tng == 0
        end

        testset "Addition" do
            terracode
                var x = Td {-4, 3}
                var y = Td {6, -9}
                var z = x + y
            end
            test z.val == x.val + y.val
            test z.tng == x.tng + y.tng
        end

        testset "Substraction" do
            terracode
                var x = Td {-4, 3}
                var y = Td {6, -9}
                var z = x - y
            end
            test z.val == x.val - y.val
            test z.tng == x.tng - y.tng
        end

        testset "Multiplication" do
            terracode
                var x = Td {-4, 3}
                var y = Td {6, -9}
                var z = x * y
            end
            test z.val == x.val * y.val
            test z.tng == x.tng * y.val + x.val * y.tng
        end

        testset "Division" do
            terracode
                var x = Td {-4, 3}
                var y = Td {6, -9}
                var z = x / y
            end
            test z.val == x.val / y.val
            test z.tng == x.tng / y.val - x.val * y.tng / (y.val * y.val)
        end

        testset "Exponential function" do
            terracode
                var f = lambda.new([terra(x: Td) return tmath.exp(-3 * x) end])
                var x = Td {0.25, 1}
                var y = f(x)
                var val: T = 0.4723665527410147
                var tng: T = -1.417099658223044
            end
            test tmath.isapprox(y.val, val, tol)
            test tmath.isapprox(y.tng, tng, tol)
        end

        testset "Exponential minus one function" do
            terracode
                var f = lambda.new([terra(x: Td) return tmath.expm1(-3 * x) end])
                var x = Td {0.25, 1}
                var y = f(x)
                var val: T = 0.4723665527410147 - 1.0
                var tng: T = -1.417099658223044
            end
            test tmath.isapprox(y.val, val, tol)
            test tmath.isapprox(y.tng, tng, tol)
        end

        testset "Error function" do
            terracode
                var f = lambda.new([terra(x: Td) return tmath.erf(5 * x) end])
                var x = Td {1.0 / 6.0, 1}
                var y = f(x)
                var val: T = 0.7614071706835646
                var tng: T = 2.817290776536529
            end
            test tmath.isapprox(y.val, val, tol)
            test tmath.isapprox(y.tng, tng, tol)
        end

        testset "Sine function" do
            terracode
                var f = lambda.new([terra(x: Td) return tmath.sin(2 * tmath.pi * x) end])
                var x = Td {-1.0 / 3.0, 1}
                var y = f(x)
                var val: T = -0.8660254037844386
                var tng: T = -3.141592653589793
            end
            test tmath.isapprox(y.val, val, tol)
            test tmath.isapprox(y.tng, tng, tol)
        end

        testset "Cosine function" do
            terracode
                var f = lambda.new([terra(x: Td) return tmath.cos(2 * tmath.pi * x) end])
                var x = Td {-1.0 / 3.0, 1}
                var y = f(x)
                var val: T = -0.5
                var tng: T = 5.441398092702653
            end
            test tmath.isapprox(y.val, val, tol)
            test tmath.isapprox(y.tng, tng, tol)
        end

        testset "Square root function" do
            terracode
                var f = lambda.new([terra(x: Td) return tmath.sqrt(x / 7) end])
                var x = Td {9, 1}
                var y = f(x)
                var val: T = 1.1338934190276815
                var tng: T = 0.0629940788348712
            end
            test tmath.isapprox(y.val, val, tol)
            test tmath.isapprox(y.tng, tng, tol)
        end

        testset "Integer power function" do
            terracode
                var f = lambda.new([terra(x: Td, y: int32) return tmath.pow(2 * x, y) end])
                var x = Td {2.5, 1}
                var y = 9
                var z = f(x, y)
                var val: T = 1.953125e6
                var tng: T = 7.03125e6
            end
            test tmath.isapprox(z.val, val, tol)
            test tmath.isapprox(z.tng, tng, tol)
        end

        testset "Power function" do
            terracode
                var f = lambda.new([terra(x: Td, y: Td) return tmath.pow(2 * x, y / 3) end])
                var x = Td {2.5, 1}
                var y = Td {1.25, 1}
                var z = f(x, y)
                var val: T = 1.95540851400894
                var tng: T = 1.374937617915628
            end
            test tmath.isapprox(z.val, val, tol)
            test tmath.isapprox(z.tng, tng, tol)
        end

        testset "Finite Difference of exponential minus one" do
            terracode
                var f = lambda.new([terra(x: Td) return tmath.fdexpm1(x / 4) end])
                var x = Td {2.5, 1}
                var z = f(x)
                var val: T = 1.3891935318915558
                var tng: T = 0.19162097021626667
            end
            test tmath.isapprox(z.val, val, tol)
            test tmath.isapprox(z.tng, tng, tol)
        end

        testset "Finite Difference of exponential minus one at zero" do
            terracode
                var f = lambda.new([terra(x: Td) return tmath.fdexpm1(x / 4) end])
                var x = Td {0, 1}
                var z = f(x)
                var val: T = 1.0
                var tng: T = 0.125
            end
            test tmath.isapprox(z.val, val, tol)
            test tmath.isapprox(z.tng, tng, tol)
        end

        testset "Finite Difference of error function" do
            terracode
                var f = lambda.new([terra(x: Td) return tmath.fderf(3 * x) end])
                var x = Td {2.5, 1}
                var z = f(x)
                var val: T = 0.13333333333333333
                var tng: T = -0.05333333333333334
            end
            test tmath.isapprox(z.val, val, tol)
            test tmath.isapprox(z.tng, tng, tol)
        end

        testset "Finite Difference of error function at zero" do
            terracode
                var f = lambda.new([terra(x: Td) return tmath.fderf(3 * x) end])
                var x = Td {0, 1}
                var z = f(x)
                var val: T = 1.1283791670955126
                var tng: T = 0.
            end
            test tmath.isapprox(z.val, val, tol)
            test tmath.isapprox(z.tng, tng, tol)
        end

        testset "Mixed expression" do
            terracode
                var f = lambda.new([
                    terra(x: Td)
                        var arg = 2 * tmath.sqrt(x)
                        return tmath.sqrt(tmath.pi) * tmath.erf(arg) / arg
                    end
                ])
                var x = Td {0.1, 1}
                var y = f(x)
                var val: T = 1.7625080698798488
                var tng: T = -2.1093398890428485
            end
            test tmath.isapprox(y.val, val, tol)
            test tmath.isapprox(y.tng, tng, tol)
        end
    end
end
