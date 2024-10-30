local Alloc = require("alloc")
local rn = require("range")
local Stack = require("example_stack_heap")

local DefaultAllocator =  Alloc.DefaultAllocator()

import "terratest/terratest"

testenv "range reductions" do

    local T = int
    local stack = Stack.DynamicStack(T)
    local unitrange = rn.Unitrange(T)
    local steprange = rn.Steprange(T)

    terracode
        var alloc : DefaultAllocator
        var j = stack.new(&alloc, 10)
        var s = stack.new(&alloc, 10)
    end

    testset "product - 2" do
        terracode
            var U = stack.new(&alloc, 10)
            var V = stack.new(&alloc, 10)
            for t in rn.product(unitrange{1, 4}, unitrange{2, 4}) >> rn.reduce("+") do
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
            for t in rn.product(unitrange{1, 4}, unitrange{2, 4}, unitrange{3, 5}) do
                U:push(t._0)
                V:push(t._1)
                W:push(t._2)
            end
        end
        test U:size()==12
        test U:get(0)==1 and V:get(0)==2 and W:get(0)==3
        test U:get(11)==3 and V:get(11)==3 and W:get(11)==4
    end

end