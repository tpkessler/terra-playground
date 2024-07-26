import "terratest/terratest"
local io = terralib.includec('stdio.h')
local Alloc = require('alloc')
local Gauss = require("gauss")
local math = require("mathfuns")
local Vector = require("dvector")
local Poly = require("poly")

local Allocator = Alloc.Allocator
local DefaultAllocator =  Alloc.DefaultAllocator()
local dvec = Vector.DynamicVector(double)

math.isapprox = terralib.overloadedfunction("isapprox")
math.isapprox:adddefinition(terra(a : double, b : double, atol : double)
    return math.abs(b-a) < atol
end)

math.isapprox:adddefinition(terra(v : dvec, w : dvec, atol : double)
    if v:size() == w:size() then
        var s = 0.0
        for i = 0, v:size() do
            var e = v(i) - w(i)
            s = s + e * e
        end
        return math.sqrt(s) < atol
    end
    return false
end)

testenv "Gauss Legendre quadrature" do

    terracode
        var alloc : DefaultAllocator
    end

    for N=1, 50, 3 do

        local D = 2*N-1
        local poly = Poly.Polynomial(double, D)

        terracode 
            --create polynomial sum_{i=0}^{D} x^i dx
            var p = poly{}
            for k = 0, D do
                p.coeffs(k) = 1.0
            end
            --exact value integral of int_[-1,1] p(x) dx
            var S = 0.0
            for j = 1, D+1, 2 do
                var J : double = j
                S = S + 2.0 / J
            end
        end

        testset(N) "GL " do
            terracode
                var x, w = Gauss.legendre(&alloc, N)
                var s = 0.0
                for i = 0, N do
                    s = s + w(i) * p(x(i))
                end
            end
            test x:size() == N and w:size() == N
            test math.isapprox(w:sum(), 2.0, 1e-13)
            test math.isapprox(s, S, 1e-13)
        end
    end

end

testenv "Gauss Chebyshev quadrature" do

    local poly2 = Poly.Polynomial(double, 3)
    local poly3 = Poly.Polynomial(double, 4)
    local N = 10

    terracode
        var alloc : DefaultAllocator
        var p2 = poly2.from(0.0,0.0,1.0)
        var p3 = poly3.from(0.0,0.0,0.0,1.0)
    end

    for N=2, 50, 7 do

        testset(N) "Chebyshev t" do
            terracode
                var x, w = Gauss.chebyshev_t(&alloc, N)
                var s2, s3 = 0.0, 0.0
                for i = 0, N do
                    s2 = s2 + w(i) * p2(x(i))
                    s3 = s3 + w(i) * p3(x(i))
                end
            end
            test x:size() == N and w:size() == N
            test math.isapprox(s2, math.pi/2., 1e-14)
            test math.isapprox(s3, 0., 1e-14)
        end

        testset(N) "Chebyshev u" do
            terracode
                var x, w = Gauss.chebyshev_u(&alloc, N)
                var s2, s3 = 0.0, 0.0
                for i = 0, N do
                    s2 = s2 + w(i) * p2(x(i))
                    s3 = s3 + w(i) * p3(x(i))
                end
            end
            test x:size() == N and w:size() == N
            test math.isapprox(s2, math.pi/8., 1e-14)
            test math.isapprox(s3, 0., 1e-14)
        end

        testset(N) "Chebyshev v" do
            terracode
                var x, w = Gauss.chebyshev_v(&alloc, N)
                var s2, s3 = 0.0, 0.0
                for i = 0, N do
                    s2 = s2 + w(i) * p2(x(i))
                    s3 = s3 + w(i) * p3(x(i))
                end
            end
            test x:size() == N and w:size() == N
            test math.isapprox(s2, math.pi/2., 1e-14)
            test math.isapprox(s3, 3.*math.pi/8., 1e-14)
        end

        testset(N) "Chebyshev w" do
            terracode
                var x, w = Gauss.chebyshev_w(&alloc, N)
                var s2, s3 = 0.0, 0.0
                for i = 0, N do
                    s2 = s2 + w(i) * p2(x(i))
                    s3 = s3 + w(i) * p3(x(i))
                end
            end
            test x:size() == N and w:size() == N
            test math.isapprox(s2, math.pi/2., 1e-14)
            test math.isapprox(s3, -3.*math.pi/8., 1e-14)
        end
    end
end


testenv "Gauss Jacobi quadrature" do

    terracode
        var alloc : DefaultAllocator
    end

    for N=1, 50, 3 do

        testset(N) "reproduce Gauss-Legendre" do
            terracode
                var x, w = Gauss.jacobi(&alloc, N, 0, 0)
                var xref, wref = Gauss.legendre(&alloc, N)
            end
            test x:size() == N and w:size() == N
            test math.isapprox(xref, x, 1e-13)
            test math.isapprox(wref, w, 1e-13)
        end

        testset(N) "reproduce Gauss-Chebyshev of the 1st kind" do
            terracode
                var x, w = Gauss.jacobi(&alloc, N, -0.5, -0.5)
                var xref, wref = Gauss.chebyshev_t(&alloc, N)
            end
            test x:size() == N and w:size() == N
            test math.isapprox(xref, x, 1e-13)
            test math.isapprox(wref, w, 1e-13)
        end

        testset(N) "reproduce Gauss-Chebyshev of the 2st kind" do
            terracode
                var x, w = Gauss.jacobi(&alloc, N, 0.5, 0.5)
                var xref, wref = Gauss.chebyshev_u(&alloc, N)
            end
            test x:size() == N and w:size() == N
            test math.isapprox(xref, x, 1e-13)
            test math.isapprox(wref, w, 1e-13)
        end

        testset(N) "reproduce Gauss-Chebyshev of the 3rd kind" do
            terracode
                var x, w = Gauss.jacobi(&alloc, N, -0.5, 0.5)
                var xref, wref = Gauss.chebyshev_v(&alloc, N)
            end
            test x:size() == N and w:size() == N
            test math.isapprox(xref, x, 1e-13)
            test math.isapprox(wref, w, 1e-13)
        end

        testset(N) "reproduce Gauss-Chebyshev of the 4rd kind" do
            terracode
                var x, w = Gauss.jacobi(&alloc, N, 0.5, -0.5)
                var xref, wref = Gauss.chebyshev_w(&alloc, N)
            end
            test x:size() == N and w:size() == N
            test math.isapprox(xref, x, 1e-13)
            test math.isapprox(wref, w, 1e-13)
        end
    end

    testset "n = 1" do
        terracode
            var a, b = 1.0, 2.0
            var x, w = Gauss.jacobi(&alloc, 1, a, b)
        end
        test x:size() == 1 and w:size() == 1
        test math.isapprox(x(0), (b - a) / (a + b + 2), 1e-13)
        test math.isapprox(w(0), 1.3333333333333333, 1e-13)
    end

    testset "a specific n = 10" do
        terracode
            var x, w = Gauss.jacobi(&alloc, 10, 0.2, -1./30.)
        end
        test x:size() == 10 and w:size() == 10
        test math.isapprox(x(6), 0.41467011760532446, 1e-13)
        test math.isapprox(w(2), 0.24824523988590236, 1e-13)
    end

    testset "a specific n = 42" do
        terracode
            var x, w = Gauss.jacobi(&alloc, 42, -.1, .3)
        end
        test x:size() == 42 and w:size() == 42
        test math.isapprox(x(36), 0.912883347814032, 1e-13)
        test math.isapprox(w(36), 0.046661910947553, 1e-13)
    end

end