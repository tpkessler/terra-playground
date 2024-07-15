import "terratest/terratest"
local io = terralib.includec('stdio.h')
local Alloc = require('alloc')
local Gauss = require("gausslegendre")
local Math = require("mathfuns")
local Vector = require("dvector")
local Poly = require("poly")

local Allocator = Alloc.Allocator
local DefaultAllocator =  Alloc.DefaultAllocator()
local dvec = Vector.DynamicVector(double)

Math.isapprox = terra(a : double, b : double, atol : double)
    return Math.abs(b-a) < atol
end

testenv "Gauss Legendre quadrature" do

    terracode
        var alloc : DefaultAllocator
    end

    for N=1,100 do

        local D = 2*N-1
        local poly = Poly.Polynomial(double, D)

        testset(N) "GL " do
            terracode
                var x, w = Gauss.legendre(&alloc, N)
                var y = dvec.new(&alloc, N)
                var p = poly{}
                for k = 0, D do
                    p.coeffs(k) = 1.0
                end
                var s = 0.0
                for i = 0, N do
                    s = s + w(i) * p(x(i))
                end
                var S = 0.0
                for j = 1, D+1, 2 do
                    var J : double = j
                    S = S + 2.0 / J
                end
            end
            test x:size() == N and w:size() == N
            test Math.isapprox(w:sum(), 2.0, 1e-13)
            test Math.isapprox(s, S, 1e-13)
        end
    end

end