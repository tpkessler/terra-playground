import "terratest/terratest"
local io = terralib.includec('stdio.h')
local Alloc = require('alloc')
local Gauss = require("gauss")
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

    for N=1, 100, 3 do

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

testenv "Gauss Jacobi quadrature" do

    terracode
        var alloc : DefaultAllocator
    end

    for N=1, 50, 3 do

        local D = 2*N-1
        local poly = Poly.Polynomial(double, D)

        testset(N) "reproduce Gauss-Legendre" do
            terracode
                var x, w = Gauss.jacobi(&alloc, N, 0, 0)
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
            test Math.isapprox(s, S, 1e-10)
        end
    end

end