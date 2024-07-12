import "terratest/terratest"

local Alloc = require('alloc')
local Gauss = require("gausslegendre")
local Math = require("mathfuns")

local Allocator = Alloc.Allocator
local DefaultAllocator =  Alloc.DefaultAllocator()


Math.isapprox = terra(a : double, b : double, atol : double)
    return Math.abs(b-a) < atol
end

print(Math.isapprox.type)

testenv "Gauss Legendre quadrature" do

    terracode
        var alloc : DefaultAllocator
    end

    for N=1,5 do
        testset(N) "GL " do
            terracode
                var x, w = Gauss.legendre(&alloc, N)
            end
            test x:size() == N and w:size() == N
            test Math.isapprox(w:sum(), 2.0, 1e-15)
        end
    end

end