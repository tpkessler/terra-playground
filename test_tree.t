-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local tree = require("tree")
local alloc = require("alloc")
local io = terralib.includec("stdio.h")

local DefaultAllocator = alloc.DefaultAllocator()

import "terratest/terratest"

for _, T in pairs{float, double, int32, int64, uint64} do
    local btree = tree.BinaryTree(T)
    testenv(T) "Tree construction" do
        terracode
            var A: alloc.DefaultAllocator()
        end

        testset "Grow left" do
            terracode
                var t = btree.new(&A, 1, nil)
                t:grow_left(&A, 2)
            end

            test t.data == 1
            test t.left.data == 2
            test t.left.right.ptr == nil
            test t.left.left.ptr == nil
            test t.right.ptr == nil
        end

        testset "Grow right" do
            terracode
                var t = btree.new(&A, 1, nil)
                t:grow_right(&A, 2)
            end

            test t.data == 1
            test t.right.data == 2
            test t.right.left.ptr == nil
            test t.right.right.ptr == nil
            test t.left.ptr == nil
        end

        testset "Grow" do
            terracode
                var t = btree.new(&A, 1, nil)
                t:grow(&A, 2, 3)
            end

            test t.data == 1
            test t.left.data == 2
            test t.left.right.ptr == nil
            test t.left.left.ptr == nil
            test t.right.data == 3
            test t.right.left.ptr == nil
            test t.right.right.ptr == nil
        end
    end
end
