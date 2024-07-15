import "terratest/terratest"
local Alloc = require('alloc')
local Gauss = require("gausschebyshev")
local Math = require("mathfuns")
local Vector = require("dvector")
local Poly = require("poly")

local Allocator = Alloc.Allocator
local DefaultAllocator =  Alloc.DefaultAllocator()
local dvec = Vector.DynamicVector(double)

Math.isapprox = terra(a : double, b : double, atol : double)
    return Math.abs(b-a) < atol
end

testenv "Gauss Chebyshev quadrature - x^2" do

    local poly2 = Poly.Polynomial(double, 3)
    local N = 10

    terracode
        var alloc : DefaultAllocator
        var p2 = poly2.from(0.0,0.0,1.0)
    end

    testset "Chebyshev t" do
        terracode
            var x, w = Gauss.chebyshev_t(&alloc, N)
            var s = 0.0
            for i = 0, N do
                s = s + w(i) * p2(x(i))
            end
        end
        test x:size() == N and w:size() == N
        test Math.isapprox(s, math.pi/2., 1e-14)
    end

    testset "Chebyshev u" do
        terracode
            var x, w = Gauss.chebyshev_u(&alloc, N)
            var s = 0.0
            for i = 0, N do
                s = s + w(i) * p2(x(i))
            end
        end
        test x:size() == N and w:size() == N
        test Math.isapprox(s, math.pi/8., 1e-14)
    end

    testset "Chebyshev v" do
        terracode
            var x, w = Gauss.chebyshev_v(&alloc, N)
            var s = 0.0
            for i = 0, N do
                s = s + w(i) * p2(x(i))
            end
        end
        test x:size() == N and w:size() == N
        test Math.isapprox(s, math.pi/2., 1e-14)
    end

    testset "Chebyshev w" do
        terracode
            var x, w = Gauss.chebyshev_w(&alloc, N)
            var s = 0.0
            for i = 0, N do
                s = s + w(i) * p2(x(i))
            end
        end
        test x:size() == N and w:size() == N
        test Math.isapprox(s, math.pi/2., 1e-14)
    end
end

testenv "Gauss Chebyshev quadrature - x^3" do

    local poly3 = Poly.Polynomial(double, 4)
    local N = 10

    terracode
        var alloc : DefaultAllocator
        var p3 = poly3.from(0.0,0.0,0.0,1.0)
    end

    testset "Chebyshev t" do
        terracode
            var x, w = Gauss.chebyshev_t(&alloc, N)
            var s = 0.0
            for i = 0, N do
                s = s + w(i) * p3(x(i))
            end
        end
        test x:size() == N and w:size() == N
        test Math.isapprox(s, 0., 1e-14)
    end

    testset "Chebyshev u" do
        terracode
            var x, w = Gauss.chebyshev_u(&alloc, N)
            var s = 0.0
            for i = 0, N do
                s = s + w(i) * p3(x(i))
            end
        end
        test x:size() == N and w:size() == N
        test Math.isapprox(s, 0., 1e-14)
    end

    testset "Chebyshev v" do
        terracode
            var x, w = Gauss.chebyshev_v(&alloc, N)
            var s = 0.0
            for i = 0, N do
                s = s + w(i) * p3(x(i))
            end
        end
        test x:size() == N and w:size() == N
        test Math.isapprox(s, 3.*math.pi/8., 1e-14)
    end

    testset "Chebyshev w" do
        terracode
            var x, w = Gauss.chebyshev_w(&alloc, N)
            var s = 0.0
            for i = 0, N do
                s = s + w(i) * p3(x(i))
            end
        end
        test x:size() == N and w:size() == N
        test Math.isapprox(s, -3.*math.pi/8., 1e-14)
    end
end