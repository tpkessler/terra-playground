-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local simd = require("simd")

import "terratest/terratest"

for _, T in pairs{int32, int64, float, double} do
    for _, N in pairs{4, 8, 16, 32, 64} do
        testenv(T, N) "SIMD" do
            local SIMD = simd.VectorFactory(T, N)
            testset "Cast from scalar" do
                terracode
                    var a = [T](-2)
                    var v: SIMD = a
                    var av: T[N]
                    v:store(&av[0])
                end
                for i = 0, N - 1 do
                    test av[i] == a
                end
            end

            testset "Cast from vector" do
                terracode
                    var a = [T](-2)
                    var v: SIMD = (
                        escape
                            local arg = terralib.newlist()
                            for i = 0, N - 1 do
                                arg:insert(`a)
                            end
                            emit `vectorof(T, [arg])
                        end
                    )
                    var av: T[N]
                    v:store(&av[0])
                end
                for i = 0, N - 1 do
                    test av[i] == a
                end
            end

            testset "Cast from pointer" do
                terracode
                    var a = [T](-2)
                    var v: SIMD = (
                        escape
                            local arg = terralib.newlist()
                            for i = 0, N - 1 do
                                arg:insert(`a)
                            end
                            emit (
                                quote
                                    var arr = arrayof(T, [arg])
                                in
                                    &arr[0]
                                end
                            )
                        end
                    )
                    var av: T[N]
                    v:store(&av[0])
                end
                for i = 0, N - 1 do
                    test av[i] == a
                end
            end

            testset "Horizontal sum" do
                terracode
                    var v: SIMD = (
                        escape
                            local arg = terralib.newlist()
                            for i = 0, N - 1 do
                                arg:insert(`i)
                            end
                            emit `vectorof(T, [arg])
                        end
                    )
                    var sum = v:hsum()
                end
                test sum == (N * (N - 1)) / 2
            end
        end
    end
end
