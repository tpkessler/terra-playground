-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local base = require("base")
local darray = require("darray")
local random = require("random")
local range = require("range")
local tree = require("tree")
local thread = require("thread")
local tmath = require("tmath")

import "terratest@v1/terratest"

require("terralibext")

local TracingAllocator = alloc.TracingAllocator()


testenv "Basic data structures" do
    terracode
        var A: alloc.DefaultAllocator()
    end

    testset "Mutex" do
        terracode
            var mtx: thread.mutex
        end
        test mtx:lock() == 0
        test mtx:unlock() == 0
    end

    testset "Conditional" do
        terracode
            var cnd: thread.cond
        end
        test cnd:signal() == 0
        test cnd:broadcast() == 0
    end


    testset "Thread" do
        local terra go(i: int, a: &int)
            a[i] = 2 * i + 1
            return 0
        end

        local NTHREADS = 3

        terracode
            var t: thread.thread[NTHREADS]
            var a: int[NTHREADS]
            for i = 0, NTHREADS do
                t[i] = thread.thread.new(&A, go, i, &a[0])
            end
            for i = 0, NTHREADS do
                t[i]:join()
            end
        end

        for i = 0, NTHREADS - 1 do
            test a[i] == 2 * i + 1
        end
    end


    testset "Join threads" do
        local terra go(i: int, a: &int)
            a[i] = 2 * i + 1
            return 0
        end

        local NTHREADS = 11

        terracode
            var a: int[NTHREADS]
            var t: thread.thread[NTHREADS]
            do
                var joiner = thread.join_threads {t}
                for i = 0, NTHREADS do
                    t[i] = thread.thread.new(&A, go, i, &a[0])
                end
            end
        end

        for i = 0, NTHREADS - 1 do
            test a[i] == 2 * i + 1
        end
    end

    testset "Lock guard" do
        local gmutex = global(alloc.SmartObject(thread.mutex))
        local PCG = random.MinimalPCG

        local terra do_work(rng: &PCG(double))
            var max: uint64 = 10000000ull
            var sum: double = 0
            for i = 0, max do
                sum = i * sum + rng:random_normal(2.235, 0.64)
                sum = sum / (i + 1)
            end
            return sum
        end


        local terra sum(i: int, total: &double)
            var rng = [PCG(double)].new(2385287, i)
            var res = do_work(&rng)
            do
                var guard: thread.lock_guard = gmutex.ptr
                @total = @total + res
            end
            return 0
        end

        local NTHREADS = 5
        terracode
            gmutex = [gmutex.type].new(&A)
            var total: double = 0
            var t: thread.thread[NTHREADS]
            for i = 0, NTHREADS do
                t[i] = thread.thread.new(&A, sum, i, &total)
            end

            for i = 0, NTHREADS do
                t[i]:join()
            end
            total = total / NTHREADS
            var ref = 2.234985325075695e+00
        end

        test tmath.isapprox(total, ref, 1e-15)
        
        gmutex:get():__dtor()
    end

    testset "Thread pool" do
        local PCG = random.MinimalPCG
        local terra do_work(rng: &PCG(double))
            var max: uint64 = 10000000ull
            var sum: double = 0
            for i = 0, max do
                sum = i * sum + rng:random_normal(2.235, 0.64)
                sum = sum / (i + 1)
            end
            return sum
        end

        local terra heavy_work(i: int, tsum: &double, mtx: &thread.mutex)
            var rng = [PCG(double)].new(2385287, i)
            var sum = do_work(&rng)
            -- var guard: thread.lock_guard = mtx
            @tsum = @tsum + sum
            return 0
        end

        local NTHREADS = 4
        local NJOBS = 10
        terracode
            var sum = 0.0
            var mtx: thread.mutex
            do
                var tp = thread.threadpool.new(&A, NTHREADS)
                for i = 0, NJOBS do
                    tp:submit(&A, heavy_work, i, &sum, &mtx)
                end
            end
            sum = sum / NJOBS
            var ref = 2.235004790726248e+00
        end
        test tmath.isapprox(sum, ref, 1e-15)
    end

end

testenv "Parallel for" do
    local lambda = require("lambda")
    local range = require("range")

    local NITEMS = 65
    testset "Linear range" do
        local terra go(i: int, a: &double)
            a[i] = -i - 1
        end

        terracode
            var A: alloc.DefaultAllocator()
            var rn = [range.Unitrange(int)].new(0, NITEMS)
            var a: double[NITEMS]
            thread.parfor(&A, rn, lambda.new(go, {a = &a[0]}))
        end

        for i = 0, NITEMS - 1 do
            test a[i] == -i - 1
        end
    end

    testset "Unstructured range" do

        local dtree = tree.BinaryTree(double)
        terracode
            var A: alloc.DefaultAllocator()
            var t = dtree.new(&A, 4.0, nil)
            var v = [darray.DynamicVector(double)].zeros(&A, 5)
            t:grow(&A, 2.0, 5.0)
            t.left:grow(&A, 1.0, 3.0)
            var go = lambda.new([
                terra(it: tuple(int32, double), v: v.type)
                    var i, x = it
                    v(i) = x
                end
            ], {v = v})
            thread.parfor(
                &A, range.zip([range.Unitrange(int32)].new(0, 5), t.ptr), go
            )
        end

        for i = 1, 5 do
            test v(i - 1) == i
        end
    end
end
