-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest"
import "terraform"

local io = terralib.includec("stdio.h")
local alloc = require("alloc")
local concepts = require("concepts")
local nfloat = require("nfloat")
local rn = require("range")
local stack = require("stack")

local DefaultAllocator =  alloc.DefaultAllocator()
local float256 = nfloat.FixedFloat(256)

for _, T in ipairs{int, double, float256} do

    local stack = stack.DynamicStack(T)

    testenv(T) "containers" do

        local unitrange = rn.Unitrange(T)
        local steprange = rn.Steprange(T)

        terracode
            var alloc : DefaultAllocator
            var s = stack.new(&alloc, 10)
            var t = stack.new(&alloc, 10)
        end

        local smrtptr = alloc.SmartBlock(T)

        testset "collect in a block" do
            terracode
                var x : smrtptr = alloc:new(sizeof(T), 3)
                var y : smrtptr = alloc:new(sizeof(T), 3)
                y:set(0, 1)
                y:set(1, 2)
                y:set(2, 3)
                y:collect(&x)
            end
            test x:isempty() == false
            test x:size() == 3
            test x:get(0) == 1
            test x:get(1) == 2
            test x:get(2) == 3
        end

        testset "collect in a stack" do
            terracode
                var r = unitrange.new(1, 4)
                r:pushall(&s)
                s:pushall(&t)

            end
            test s:size() == 3 and t:size() == 3
            test s:get(0)==1 and t:get(0)==1
            test s:get(1)==2 and t:get(1)==2
            test s:get(2)==3 and t:get(2)==3
        end

    end

    testenv(T) "linear ranges - not including last element" do

        local unitrange = rn.Unitrange(T)
        local steprange = rn.Steprange(T)

        terracode
            var alloc : DefaultAllocator
            var s = stack.new(&alloc, 10)
        end

        testset "unitrange" do
            terracode
                var r = unitrange.new(1, 4)
                r:pushall(&s)
            end
            test s:size()==3
            test s:get(0)==1
            test s:get(1)==2
            test s:get(2)==3
            test r.b==4
            test r(0)==1
            test r(1)==2
            test r(2)==3
        end

        testset "steprange - step=2, %0" do
            terracode
                var r = steprange.new(1, 7, 2)
                r:pushall(&s)
            end
            test s:size()==3
            test s:get(0)==1
            test s:get(1)==3
            test s:get(2)==5
            test r.b==7
            test r(0)==1
            test r(1)==3
            test r(2)==5
        end

        testset "steprange - step=2, %1" do
            terracode
                var r = steprange.new(1, 6, 2)
                r:pushall(&s)
            end
            test s:size()==3
            test s:get(0)==1
            test s:get(1)==3
            test s:get(2)==5
            test r.b==7
            test r(0)==1
            test r(1)==3
            test r(2)==5
        end

        testset "steprange - backward step=1" do
            terracode
                var r = steprange.new(1, -2, -1)
                r:pushall(&s)
            end
            test s:size()==3
            test s:get(0)==1
            test s:get(1)==0
            test s:get(2)==-1
            test r.b==-2
            test r(0)==1
            test r(1)==0
            test r(2)==-1
        end

        testset "steprange - backward step=2, %0" do
            terracode
                var r = steprange.new(1, -5, -2)
                r:pushall(&s)
            end
            test s:size()==3
            test s:get(0)==1
            test s:get(1)==-1
            test s:get(2)==-3
            test r.b==-5
            test r(0)==1
            test r(1)==-1
            test r(2)==-3
        end

        testset "steprange - backward step=2, %1" do
            terracode
                var r = steprange.new(1, -4, -2)
                r:pushall(&s)
            end
            test s:size()==3
            test s:get(0)==1
            test s:get(1)==-1
            test s:get(2)==-3
            test r.b==-5
            test r(0)==1
            test r(1)==-1
            test r(2)==-3
        end

    end

    testenv(T) "linear ranges - including last element" do

        local unitrange = rn.Unitrange(T)
        local steprange = rn.Steprange(T)

        terracode
            var alloc : DefaultAllocator
            var s = stack.new(&alloc, 10)
        end

        testset "unitrange" do
            terracode
                var r = unitrange.new(1, 3, rn.include_last)
                r:pushall(&s)
            end
            test s:size() == 3
            test s:get(0)==1
            test s:get(1)==2
            test s:get(2)==3
            test r.b ==4
            test r(0)==1
            test r(1)==2
            test r(2)==3
        end

        testset "steprange - step=2, %0" do
            terracode
                var r = steprange.new(1, 5, 2, rn.include_last)
                r:pushall(&s)
            end
            test s:size()==3
            test s:get(0)==1
            test s:get(1)==3
            test s:get(2)==5
            test r.b==7
            test r(0)==1
            test r(1)==3
            test r(2)==5
        end

        testset "steprange - step=2, %1" do
            terracode
                var r = steprange.new(1, 6, 2, rn.include_last)
                r:pushall(&s)
            end
            test s:size()==3
            test s:get(0)==1
            test s:get(1)==3
            test s:get(2)==5
            test r.b==7
            test r(0)==1
            test r(1)==3
            test r(2)==5
        end

        testset "steprange - backward step=1" do
            terracode
                var r = steprange.new(1, -1, -1, rn.include_last)
                r:pushall(&s)
            end
            test s:size()==3
            test s:get(0)==1
            test s:get(1)==0
            test s:get(2)==-1
            test r.b==-2
            test r(0)==1
            test r(1)==0
            test r(2)==-1
        end

        testset "steprange - backward step=2, %0" do
            terracode
                var r = steprange.new(1, -3, -2, rn.include_last)
                r:pushall(&s)
            end
            test s:size()==3
            test s:get(0)==1
            test s:get(1)==-1
            test s:get(2)==-3
            test r.b==-5
            test r(0)==1
            test r(1)==-1
            test r(2)==-3
        end

        testset "steprange - backward step=2, %1" do
            terracode
                var r = steprange.new(1, -4, -2, rn.include_last)
                r:pushall(&s)
            end
            test s:size()==3
            test s:get(0)==1
            test s:get(1)==-1
            test s:get(2)==-3
            test r.b==-5
            test r(0)==1
            test r(1)==-1
            test r(2)==-3
        end

    end

    testenv(T) "linear ranges - infinite ranges" do

        local unitrange = rn.Unitrange(T, "infinite")
        local steprange = rn.Steprange(T, "infinite")
        
        terracode
            var alloc : DefaultAllocator
            var s = stack.new(&alloc, 10)
        end

        testset "unitrange" do
            terracode
                var r = unitrange.new(1)
                (r >> rn.take(3)):pushall(&s)
            end
            test s:size()==3
            test s:get(0)==1
            test s:get(1)==2
            test s:get(2)==3
            test r(0)==1
            test r(1)==2
            test r(2)==3
        end

        testset "steprange - step=2, %0" do
            terracode
                var r = steprange.new(1, 2)
                (r >> rn.take(3)):pushall(&s)
            end
            test s:size()==3
            test s:get(0)==1
            test s:get(1)==3
            test s:get(2)==5
            test r(0)==1
            test r(1)==3
            test r(2)==5
        end

    end
end -- for _, T in ipairs{int, double} do

local Integer = concepts.Integer
local stack = stack.DynamicStack(int)
local unitrange = rn.Unitrange(int)
local steprange = rn.Steprange(int)

testenv "range adapters" do

    terracode
        var alloc : DefaultAllocator
        var s = stack.new(&alloc, 10)
    end

    testset "transform" do
        terracode
            var x = 2
            var g = rn.transform([terra(i : int, x : int) return x * i end], {x = x})
            var range = unitrange.new(1, 4) >> g
            range:pushall(&s)
        end
        test s:size()==3
        test s:get(0)==2
        test s:get(1)==4
        test s:get(2)==6
    end

    testset "filter" do
        terracode
            var x = 1
            var range = unitrange{1, 7} >> rn.filter([terra(i : int, x : int) return i % 2 == x end], {x = x})
            range:pushall(&s)
        end
        test s:size()==3
        test s:get(0)==1
        test s:get(1)==3
        test s:get(2)==5
    end

    testset "take" do
        terracode
            var range = unitrange{1, 10} >> rn.take(3)
            range:pushall(&s)
        end
        test s:size()==3
        test s:get(0)==1
        test s:get(1)==2
        test s:get(2)==3
    end

    testset "drop" do
        terracode
            var range = unitrange{1, 10} >> rn.drop(6)
            range:pushall(&s)
        end
        test s:size()==3
        test s:get(0)==7
        test s:get(1)==8
        test s:get(2)==9
    end

    testset "take_while" do
        terracode
            var range = unitrange{1, 10} >> rn.take_while([terra(i : int) return i < 4 end])
            range:pushall(&s)
        end
        test s:size()==3
        test s:get(0)==1
        test s:get(1)==2
        test s:get(2)==3
    end

    testset "drop_while" do
        terracode
            var x = 5
            var range = unitrange{1, 10} >> rn.drop_while([terra(i : int) return i < 7 end])
            range:pushall(&s)
        end
        test s:size()==3
        test s:get(0)==7
        test s:get(1)==8
        test s:get(2)==9
    end
end

testenv "range accumulators" do

    terracode
        var alloc : DefaultAllocator
        var s = stack.new(&alloc, 10)
    end

    local f = terra(a : int, b : int)
        return a + b
    end

    testset "foldl - lvalue" do
        terracode
            var r = unitrange.new(1,4) >> rn.foldl(f)
            var v = r:accumulatefrom(4)
        end
        test v == 4 + 1+2+3
    end

    testset "foldl - rvalue" do
        terracode
            var v = (unitrange.new(1,4) >> rn.foldl(f)):accumulatefrom(4)
        end
        test v == 4 + 1+2+3
    end
    
    local g = terra(a : int, b : int, c : int)
        return a + b + c
    end

    testset "foldl - lvalue with capture" do
        terracode
            var r = unitrange.new(1,4) >> rn.foldl(g, {c = 1})
            var v = r:accumulatefrom(4)
        end
        test v == 4 + 1+2+3 + 3
    end

    testset "foldl - rvalue with capture" do
        terracode
            var v = (unitrange.new(1,4) >> rn.foldl(g, {c = 1})):accumulatefrom(4)
        end
        test v == 4 + 1+2+3 + 3
    end

    local h = terra(save : &int, b : int)
        @save = @save + b 
    end

    testset "foldl - by reference" do
        terracode
            var r = unitrange.new(1,4) >> rn.foldl(h)
            var x = 4
            r:accumulatefrom(&x)
        end
        test x == 4 + 1+2+3
    end

end

testenv "range composition" do

    terracode
        var alloc : DefaultAllocator
        var s = stack.new(&alloc, 10)
    end

    testset "compose transform and filter - lvalues" do
        terracode
            var r = unitrange{0, 5}
            var x = 0
            var y = 3
            var g = rn.filter([terra(i : int, x : int) return i % 2 == x end], {x = x})
            var h = rn.transform([terra(i : int, y : int) return y * i end], {y = y})
            var range = r >> g >> h
            range:pushall(&s)
        end
        test s:size()==3
        test s:get(0)==0
        test s:get(1)==6
        test s:get(2)==12
    end

    testset "compose transform and filter - rvalues" do
        terracode
            var x = 0
            var y = 3
            for v in unitrange{0, 5} >> 
                        rn.filter([terra(i : int, x : int) return i % 2 == x end], {x = x}) >>
                            rn.transform([terra(i : int, y : int) return y * i end], {y = y}) do
                s:push(v)
            end
        end
        test s:size()==3
        test s:get(0)==0
        test s:get(1)==6
        test s:get(2)==12
    end
end

testenv "range composition - terraform" do

    terracode
        var alloc : DefaultAllocator
        var s = stack.new(&alloc, 10)
    end

    local terraform foo(i : T, x : T) where {T : Integer}
        return i % 2 == x
    end

    local terraform bar(i : T, y : T) where {T : Integer}
        return y * i 
    end

    testset "compose transform and filter - lvalues" do
        terracode
            var r = unitrange{0, 5}
            var x = 0
            var y = 3
            var g = rn.filter(foo, {x = x})
            var h = rn.transform(bar, {y = y})
            var range = r >> g >> h
            range:pushall(&s)
        end
        test s:size()==3
        test s:get(0)==0
        test s:get(1)==6
        test s:get(2)==12
    end
end

testenv "range combiners" do

    terracode
        var alloc : DefaultAllocator
        var j = stack.new(&alloc, 10)
        var s = stack.new(&alloc, 10)
    end

    testset "join - 1" do
        terracode
            var range = rn.join(unitrange{1, 4})
            for v in range do
                s:push(v)
            end
        end
        test s:size()==3
        for i = 1, 3 do
            test s:get([i-1]) == i
        end
    end

    testset "join - 2" do
        terracode
            var r = unitrange.new(3, 5)
            r:pushall(&j)
            var range = rn.join(unitrange{1, 3}, &j)
            for v in range do
                s:push(v)
            end
        end
        test s:size()==4
        for i = 1, 4 do
            test s:get([i-1]) == i
        end
    end

    testset "join - 3" do
        terracode
            var r = unitrange.new(3, 5)
            r:pushall(&j)
            var range = rn.join(unitrange{1, 3}, &j, unitrange{5, 7})
            for v in range do
                s:push(v)
            end
        end
        test s:size()==6
        for i = 1, 6 do
            test s:get([i-1]) == i
        end
    end

    testset "enumerate" do
        terracode
            for i,v in rn.enumerate(unitrange{1, 4}) do
                j:push(i)
                s:push(v)
            end
        end
        test j:size()==3 and s:size()==3
        test j:get(0)==0 and s:get(0)==1
        test j:get(1)==1 and s:get(1)==2
        test j:get(2)==2 and s:get(2)==3
    end

    testset "zip - 1" do
        terracode
            var U = stack.new(&alloc, 10)
            for u in rn.zip(unitrange{1, 4}) do
                U:push(u._0)
            end
        end
        test U:size()==3
        test U:get(0)==1
        test U:get(1)==2
        test U:get(2)==3
    end

    testset "zip - 2" do
        terracode
            var U = stack.new(&alloc, 10)
            var V = stack.new(&alloc, 10)
            for t in rn.zip(unitrange{1, 4}, unitrange{2, 6}) do
                U:push(t._0)
                V:push(t._1)
            end
        end
        test U:size()==3 and V:size()==3
        test U:get(0)==1 and V:get(0)==2
        test U:get(1)==2 and V:get(1)==3
        test U:get(2)==3 and V:get(2)==4
    end

    testset "product - 1" do
        terracode
            var U = stack.new(&alloc, 10)
            for u in rn.product(unitrange{1, 4}) do
                U:push(u._0)
            end
        end
        test U:size()==3
        test U:get(0)==1
        test U:get(1)==2
        test U:get(2)==3
    end

    testset "product - 2" do
        terracode
            var U = stack.new(&alloc, 10)
            var V = stack.new(&alloc, 10)
            for t in rn.product(unitrange{1, 4}, unitrange{2, 4}, {perm={1,2}}) do
                U:push(t._0)
                V:push(t._1)
            end
        end
        test U:size()==6 and V:size()==6
        test U:get(0)==1 and V:get(0)==2
        test U:get(1)==2 and V:get(1)==2
        test U:get(2)==3 and V:get(2)==2
        test U:get(3)==1 and V:get(3)==3
        test U:get(4)==2 and V:get(4)==3
        test U:get(5)==3 and V:get(5)==3
    end

    testset "product - 3" do
        terracode
            var U = stack.new(&alloc, 16)
            var V = stack.new(&alloc, 16)
            var W = stack.new(&alloc, 16)
            for t in rn.product(unitrange{1, 4}, unitrange{2, 4}, unitrange{3, 5}, {perm={1,2,3}}) do
                U:push(t._0)
                V:push(t._1)
                W:push(t._2)
            end
        end
        test U:size()==12
        test U:get(0)==1 and V:get(0)==2 and W:get(0)==3
        test U:get(11)==3 and V:get(11)==3 and W:get(11)==4
    end

    testset "zip - 3 - reduction '+'" do
        terracode
            var W = stack.new(&alloc, 10)
            for w in rn.zip(unitrange{1, 4}, unitrange{2, 6}, unitrange{3, 7}) >> rn.reduce(rn.op.add) do
                W:push(w)
            end
        end
        test W:size() == 3
        test W:get(0) == 6
        test W:get(1) == 9
        test W:get(2) == 12
    end

    testset "product - 2 - reduction '*'" do
        terracode
            var W = stack.new(&alloc, 10)
            for w in rn.product(unitrange{1, 4}, unitrange{2, 4}, {perm={1,2}}) >> rn.reduce(rn.op.mul) do
                W:push(w)
            end
        end
        test W:size() == 6
        test W:get(0) == 2
        test W:get(1) == 4
        test W:get(2) == 6
        test W:get(3) == 3
        test W:get(4) == 6
        test W:get(5) == 9
    end

    testset "product - 3 - reduction '*'" do
        terracode
            var W = stack.new(&alloc, 16)
            for w in rn.product(unitrange{1, 4}, unitrange{2, 4}, unitrange{3,5}, {perm={1,2,3}}) >> rn.reduce(rn.op.mul) do
                W:push(w)
            end
        end
        test W:size() == 12
        test W:get(0) == 6
        test W:get(11) == 36
    end

    testset "product - 3 - reverse" do
        terracode
            var U = stack.new(&alloc, 16)
            var V = stack.new(&alloc, 16)
            var W = stack.new(&alloc, 16)
            for t in rn.product(unitrange{1, 4}, unitrange{2, 4}, unitrange{3,5}, {perm={1,2,3}}) >> rn.reverse() do
                U:push(t._0)
                V:push(t._1)
                W:push(t._2)
            end
        end
        test U:size()==12 and V:size()==12 and W:size()==12
        test W:get(0)==1 and V:get(0)==2 and U:get(0)==3
        test W:get(11)==3 and V:get(11)==3 and U:get(11)==4
    end

end
