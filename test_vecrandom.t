-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT
--
local random = require("vecrandom")

import "terratest/terratest"

local GEN = random.VectorPCG

for K = 3, 6 do
    local N = 2 ^ K
    for _, T in pairs{float, double} do
        local RNG = GEN(T, N)
        testenv(T, N) "Vectorized PCG" do
            testset "New" do
                terracode
                    var rng = RNG.new(2352352)
                end
                test [RNG.traits.veclen == N]
                test [rng.type == RNG]
            end

            testset "Return type" do
                terracode
                    var rng = RNG.new(9586)
                    var x = rng:random_integer()
                end
                test [x.type == vector(RNG.traits.inttype, N)]
            end

            testset "Seed" do
                local V = vector(RNG.traits.inttype, N)
                local M = 7
                terracode
                    var seed = 23478
                    var x: V[M]
                    do
                        var rng = RNG.new(seed)
                        for i = 0, M do
                                x[i] = rng:random_integer()
                        end
                    end
                    var y: V[M]
                    do
                        var rng = RNG.new(seed)
                        for i = 0, M do
                                y[i] = rng:random_integer()
                        end
                    end
                end
                for i = 0, M - 1 do
                    for j = 0, N - 1 do
                        test (x[i] == y[i])[j] == true
                    end
                end
            end

            testset "Uniform distribution" do
                local M = 1024 * 1024
                terracode
                    var rng = RNG.new(28352903, 234)
                    var x = rng:random_uniform()
                    var mean = x
                    var sqmean = x * x
                    
                    for i = 1, M do
                        var x = rng:random_uniform()

                        mean = i * mean + x
                        mean = mean / (i + 1)

                        sqmean = i * sqmean + x * x
                        sqmean = sqmean / (i + 1)
                    end
                    var tol = [T](1e-3)

                    var errmean = mean - [T](0.5)
                    var boundsmean = (errmean < tol) and (errmean > -tol)

                    var errsqmean = sqmean - [T](0.33333)
                    var boundssqmean = (errsqmean < tol) and (errsqmean > -tol)
                end
                for i = 0, N - 1 do
                    test boundsmean[i] == true
                    test boundssqmean[i] == true
                end
            end
        end
    end
end
