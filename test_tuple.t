-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest"

local tupl = require("tuple")

testenv "istuple" do
    testset "Integer tuple" do
        local T = tuple(int, int)
        test [tupl.istuple(T)]
    end

    testset "Primitive type" do
        test [tupl.istuple(int) == false]
    end

    testset "Struct" do
        local struct A {}
        test [tupl.istuple(A) == false]
    end

    testset "Empty tuple" do
        test [tupl.istuple(tuple())]
    end

    testset "Mixed tuple" do
        test [tupl.istuple(tuple(int, double, tuple(int, double)))]
    end
end

testenv "unpacktuple" do
    testset "Simple tuple" do
        local lst = tupl.unpacktuple(tuple(int))
        test [#lst == 1]
        test [lst[1] == int]
    end

    testset "Mixed tuple" do
        local lst = tupl.unpacktuple(tuple(int, double, tuple(float, float)))
        test [#lst == 3]
        test [lst[1] == int]
        test [lst[2] == double]
        test [lst[3] == tuple(float, float)]
    end
end

testenv "dimensiontuple" do
    testset "Simple tuple" do
        local dim = tupl.dimensiontuple(tuple(int))
        test [#dim == 1]
        test [#dim[1] == 0]
    end

    testset "Nested tuple" do
        local dim = tupl.dimensiontuple(tuple(tuple(int, int, int), tuple(int, int)))
        test [#dim == 2]
        test [#dim[1] == 3]
        for i = 1, 3 do
            test[#dim[1][i] == 0]
        end
        test [#dim[2] == 2]
        for i = 1, 2 do
            test[#dim[2][i] == 0]
        end
    end
end

testenv "Tensor tuple" do
    testset "Vector" do
        local dim = tupl.tensortuple(tuple(int, int))
        test [#dim == 1]
        test [dim[1] == 2]
    end

    testset "Matrix" do
        local row = tuple(int, int)
        local dim = tupl.tensortuple(tuple(row, row, row))
        test [#dim == 2]
        test [dim[1] == 3]
        test [dim[2] == 2]
    end

    testset "Tensor" do
        local row = tuple(int, int)
        local matrix = tuple(row, row, row)
        local dim = tupl.tensortuple(tuple(matrix, matrix, matrix, matrix))
        test [#dim == 3]
        test [dim[1] == 4]
        test [dim[2] == 3]
        test [dim[3] == 2]
    end
end

