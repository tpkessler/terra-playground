-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileContributor: René Hiemstra <rrhiemstar@gmail.com>
--
-- SPDX-License-Identifier: MIT

local alloc = require('alloc')
local stack = require("stack")

import "terratest/terratest"


testenv "DynamicStack" do

    local T = double
    local stack = stack.DynamicStack(T)
    local DefaultAllocator =  alloc.DefaultAllocator()

    terracode
        var alloc: DefaultAllocator
        var s = stack.new(&alloc, 3)
    end

    testset "new" do
        test s:size() == 0
        test s:capacity() == 3
        test [stack.traits.eltype == T]
        test s.data:owns_resource()
    end

    testset "push" do
        terracode
            s:push(1.0)
            s:push(2.0)
        end
        test s:size() == 2
        test s:capacity() == 3
    end

    testset "pop" do
        terracode
            s:push(1.0)
            s:push(2.0)
            var x = s:pop()
        end
        test s:size() == 1
        test s:capacity() == 3
        test x == 2.0
    end

    testset "apply, set, get" do
        terracode
            s:push(1.0)
            s:push(2.0)
            s:push(3.0)
        end
        test s(0) == 1.0
        test s(1) == 2.0
        test s:get(2) == 3.0
        terracode
            s(0) = 3.0
            s(1) = 4.0
            s:set(2, 5.0)
        end
        test s(0) == 3.0
        test s(1) == 4.0
        test s:get(2) == 5.0
        test s:size() == 3
        test s:capacity() == 3
    end

    testset "insert" do
        terracode
            s:insert(0, 1.0)
            s:push(2.0)
            s:push(3.0)
            s:insert(1, 4.0)
            s:insert(3, -2.0)
        end
        test s(0) == 1.0
        test s(1) == 4.0
        test s:get(2) == 2.0
        test s:get(3) == -2.0
        test s:get(4) == 3.0
        test s:size() == 5
    end

    testset "reallocate" do
        terracode
            s:push(1.0)
            s:push(2.0)
            s:push(3.0)
            s:push(4.0) --triggering reallocate (new capacity is twice old capacity)
            s:push(5.0)
        end
        test s:size() == 5
        test s:capacity() == 7
        test s(0) == 1
        test s(1) == 2
        test s(2) == 3
        test s(3) == 4
        test s(4) == 5
    end
    
    testset "__copy" do
        terracode
            s:push(1.0)
            s:push(2.0)
            var x = s
        end
        test s.data:isempty()
        test x.data:owns_resource()
        test x:size() == 2 and x:capacity() == 3
        test x(0) == 1.0 and x(1) == 2.0
    end

    local smrtblock = alloc.SmartBlock(T)
    
    testset "__dtor" do
        terracode
            var p : &smrtblock
            do
                var v = stack.new(&alloc, 4)
                p = &v.data
            end --v:__dtor() is called here by the compiler
        end
        test p:isempty()
    end
    
end
