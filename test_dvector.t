import "terratest/terratest"

local Alloc = require('alloc')
local DVector = require('dvector')

local Allocator = Alloc.Allocator

local DefaultAllocator =  Alloc.DefaultAllocator()
local dvector = DVector.DynamicVector(double)


testenv "DynamicVector" do

    terracode
        var alloc : DefaultAllocator
    end

    testset "new" do
        terracode
            var v = dvector.new(&alloc, 3)
        end
        test v:size() == 3
    end

    testset "fill" do
        terracode
            var v = dvector.fill(&alloc, 2, 4.5)
        end
        test v:size() == 2
        test v:get(0) == 4.5
        test v:get(1) == 4.5
    end

    testset "zeros" do
        terracode
            var v = dvector.zeros(&alloc, 2)
        end
        test v:size() == 2
        test v:get(0) == 0.0
        test v:get(1) == 0.0
    end

    testset "ones" do
        terracode
            var v = dvector.ones(&alloc, 2)
        end
        test v:size() == 2
        test v:get(0) == 1.0
        test v:get(1) == 1.0
    end

    testset "from" do
        terracode
            var v = dvector.from(&alloc, 0.0, 0.5, 1.1)
        end
        test v:size() == 3
        test v:get(0) == 0.0
        test v:get(1) == 0.5
        test v:get(2) == 1.1
    end

end