-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"
local alloc = require('alloc')
local gauss = require("gauss")
local tmath = require("tmath")
local darray = require("darray")
local poly = require("poly")
local rn = require("range")

local Allocator = alloc.Allocator
local DefaultAllocator =  alloc.DefaultAllocator()
local dvec = darray.DynamicVector(double)

testenv "gauss Legendre quadrature" do

    terracode
        var alloc : DefaultAllocator
    end

    for N=1, 50, 3 do

        local D = 2*N-1
        local polynomial = poly.Polynomial(double, D)

        terracode 
            --create polynomial sum_{i=0}^{D} x^i dx
            var p = polynomial{}
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
                var x, w = gauss.legendre(&alloc, N)
                var s = 0.0
                for i = 0, N do
                    s = s + w(i) * p(x(i))
                end
            end
            test x:length() == N and w:length() == N
            test tmath.isapprox(w:sum(), 2.0, 1e-13)
            test tmath.isapprox(s, S, 1e-13)
        end
    end

end

testenv "gauss Chebyshev quadrature" do

    local poly2 = poly.Polynomial(double, 3)
    local poly3 = poly.Polynomial(double, 4)
    local N = 10

    terracode
        var alloc : DefaultAllocator
        var p2 = poly2.from({0.0,0.0,1.0})
        var p3 = poly3.from({0.0,0.0,0.0,1.0})
    end

    for N=2, 50, 7 do

        testset(N) "Chebyshev t" do
            terracode
                var x, w = gauss.chebyshev_t(&alloc, N)
                var s2, s3 = 0.0, 0.0
                for i = 0, N do
                    s2 = s2 + w(i) * p2(x(i))
                    s3 = s3 + w(i) * p3(x(i))
                end
            end
            test x:length() == N and w:length() == N
            test tmath.isapprox(s2, tmath.pi/2., 1e-14)
            test tmath.isapprox(s3, 0., 1e-14)
        end

        testset(N) "Chebyshev u" do
            terracode
                var x, w = gauss.chebyshev_u(&alloc, N)
                var s2, s3 = 0.0, 0.0
                for i = 0, N do
                    s2 = s2 + w(i) * p2(x(i))
                    s3 = s3 + w(i) * p3(x(i))
                end
            end
            test x:length() == N and w:length() == N
            test tmath.isapprox(s2, tmath.pi/8., 1e-14)
            test tmath.isapprox(s3, 0., 1e-14)
        end

        testset(N) "Chebyshev v" do
            terracode
                var x, w = gauss.chebyshev_v(&alloc, N)
                var s2, s3 = 0.0, 0.0
                for i = 0, N do
                    s2 = s2 + w(i) * p2(x(i))
                    s3 = s3 + w(i) * p3(x(i))
                end
            end
            test x:length() == N and w:length() == N
            test tmath.isapprox(s2, tmath.pi/2., 1e-14)
            test tmath.isapprox(s3, 3.*tmath.pi/8., 1e-14)
        end

        testset(N) "Chebyshev w" do
            terracode
                var x, w = gauss.chebyshev_w(&alloc, N)
                var s2, s3 = 0.0, 0.0
                for i = 0, N do
                    s2 = s2 + w(i) * p2(x(i))
                    s3 = s3 + w(i) * p3(x(i))
                end
            end
            test x:length() == N and w:length() == N
            test tmath.isapprox(s2, tmath.pi/2., 1e-14)
            test tmath.isapprox(s3, -3.*tmath.pi/8., 1e-14)
        end
    end
end

testenv "gauss Jacobi quadrature" do

    terracode
        var alloc : DefaultAllocator
    end

    for N=1, 50, 3 do

        testset(N) "reproduce gauss-Legendre" do
            terracode
                var x, w = gauss.jacobi(&alloc, N, 0, 0)
                var xref, wref = gauss.legendre(&alloc, N)
            end
            test x:length() == N and w:length() == N
            test tmath.isapprox(&xref, &x, 1e-13)
            test tmath.isapprox(&wref, &w, 1e-13)
        end

        testset(N) "reproduce gauss-Chebyshev of the 1st kind" do
            terracode
                var x, w = gauss.jacobi(&alloc, N, -0.5, -0.5)
                var xref, wref = gauss.chebyshev_t(&alloc, N)
            end
            test x:length() == N and w:length() == N
            test tmath.isapprox(&xref, &x, 1e-13)
            test tmath.isapprox(&wref, &w, 1e-13)
        end

        testset(N) "reproduce gauss-Chebyshev of the 2st kind" do
            terracode
                var x, w = gauss.jacobi(&alloc, N, 0.5, 0.5)
                var xref, wref = gauss.chebyshev_u(&alloc, N)
            end
            test x:length() == N and w:length() == N
            test tmath.isapprox(&xref, &x, 1e-13)
            test tmath.isapprox(&wref, &w, 1e-13)
        end

        testset(N) "reproduce gauss-Chebyshev of the 3rd kind" do
            terracode
                var x, w = gauss.jacobi(&alloc, N, -0.5, 0.5)
                var xref, wref = gauss.chebyshev_v(&alloc, N)
            end
            test x:length() == N and w:length() == N
            test tmath.isapprox(&xref, &x, 1e-13)
            test tmath.isapprox(&wref, &w, 1e-13)
        end

        testset(N) "reproduce gauss-Chebyshev of the 4rd kind" do
            terracode
                var x, w = gauss.jacobi(&alloc, N, 0.5, -0.5)
                var xref, wref = gauss.chebyshev_w(&alloc, N)
            end
            test x:length() == N and w:length() == N
            test tmath.isapprox(&xref, &x, 1e-13)
            test tmath.isapprox(&wref, &w, 1e-13)
        end
    end

    testset "n = 1" do
        terracode
            var a, b = 1.0, 2.0
            var x, w = gauss.jacobi(&alloc, 1, a, b)
        end
        test x:length() == 1 and w:length() == 1
        test tmath.isapprox(x(0), (b - a) / (a + b + 2), 1e-13)
        test tmath.isapprox(w(0), 1.3333333333333333, 1e-13)
    end

    testset "a specific n = 10" do
        terracode
            var x, w = gauss.jacobi(&alloc, 10, 0.2, -1./30.)
        end
        test x:length() == 10 and w:length() == 10
        test tmath.isapprox(x(6), 0.41467011760532446, 1e-13)
        test tmath.isapprox(w(2), 0.24824523988590236, 1e-13)
    end

    testset "a specific n = 42" do
        terracode
            var x, w = gauss.jacobi(&alloc, 42, -.1, .3)
        end
        test x:length() == 42 and w:length() == 42
        test tmath.isapprox(x(36), 0.912883347814032, 1e-13)
        test tmath.isapprox(w(36), 0.046661910947553, 1e-13)
    end

end

testenv "gauss hermite quadrature" do

    terracode
        var alloc : DefaultAllocator
    end

    for N=1, 30, 3 do

        local D = 2*N-1
        local polynomial = poly.Polynomial(double, D)

        local iexact = terra(K : int)
            if K % 2 == 1 then return 0.0 end
            var S = tmath.sqrt(tmath.pi)
            for k = 2, K+1, 2 do
                S = (k-1) * S / 2.0
            end
            return S
        end

        terracode 
            --create polynomial sum_{i=0}^{D} exp(-x^2) * x^i dx
            var p = polynomial{}
            for k = 0, D do
                p.coeffs(k) = 1.0
            end
            var S = 0.0
            for j = 0, D do
                S = S + iexact(j)
            end
        end


        testset(N) "hermite" do
            terracode
                var x, w = gauss.hermite(&alloc, N)
                var s = 0.0
                for t in rn.zip(&x, &w) do
                    var xx, ww = t
                    s = s + p(xx) * ww
                end
            end
            test x:length() == N and w:length() == N
            test x.data:owns_resource() and w.data:owns_resource()
            test tmath.isapprox(s, S, S * 1e-12)
        end

        testset(skip,N) "scaled hermite" do
            terracode
                var x, w = gauss.hermite(&alloc, N, {origin=1.0, scaling=0.5})
                x:print()
                w:print()
                var s0 = 0.0
                for t in rn.zip(&x, &w) do
                    var xx, ww = t
                    s0 = s0 + ww
                end
                var s2 = 0.0
                for t in rn.zip(&x, &w) do
                    var xx, ww = t
                    s2 = s2 + ww * xx * xx
                end
            end
            test x:length() == N and w:length() == N
            test tmath.isapprox(s0, tmath.sqrt(tmath.pi) / 2, 1e-12)
            if N > 1 then
                test tmath.isapprox(s2, 9 * tmath.sqrt(tmath.pi) / 16, 1e-12)
            end
        end

    end --N=1, 50, 3
    
end



local struct interval{
    _0 : double
    _1 : double
}
interval:setconvertible("tuple")

interval.metamethods.__entrymissing = macro(function(entryname, self)
    if entryname=="a" then
        return `self._0
    end
    if entryname=="b" then
        return `self._1
    end
end)

testenv "API" do

    terracode
        var alloc : DefaultAllocator
    end
    
    testset "legendre - with interval" do
        terracode
            var x,w = gauss.legendre(&alloc, 3, interval{1.0, 3.0})
        end
        test x:length() == 3 and w:length() == 3
        test tmath.isapprox(w:sum(), 2.0, 1e-13)
    end

    N = 3
    local D = 2*N-1
    local polynomial = poly.Polynomial(double, D)

    terracode
        --create polynomial sum_{i=0}^{4} x^i dx
        var p = polynomial{}
        for k = 0, D do
            p.coeffs(k) = 1.0
        end
    end

    testset "affine scaling" do
        terracode
            --int_1^4 p(x) dx
            var x,w = gauss.legendre(&alloc, N, interval{1.0, 4.0})
            var s = 0.0
            for qr in rn.zip(x,w) do
                var xx, ww = qr
                s = s + ww * p(xx)
            end
        end
        test x:length() == N and w:length() == N
        test tmath.isapprox(w:sum(), 3.0, 1e-13)
        test tmath.isapprox(s, 5997.0 / 20.0, 1e-13)
    end

    terracode
        var alloc : DefaultAllocator
        var Q_1 = gauss.legendre(&alloc, 3, interval{0.0, 3.0})
        var Q_2 = gauss.legendre(&alloc, 4, interval{1.0, 5.0})
        var Q_3 = gauss.legendre(&alloc, 5, interval{2.0, 7.0})
    end

    test Q_1.x.data:owns_resource() and Q_1.w.data:owns_resource()
    test Q_2.x.data:owns_resource() and Q_2.w.data:owns_resource()
    test Q_3.x.data:owns_resource() and Q_3.w.data:owns_resource()
    
    testset "2D tensor-product rules" do
        terracode
            var rule = gauss.productrule(Q_1, Q_2)
            var s : double = 0.0
            for qr in rn.zip(&rule.x, &rule.w) do
                var x, w = qr
                s = s + w
            end
        end
        test tmath.isapprox(s, 12.0, 1e-14)
    end
    
    testset "3D tensor-product rules - pass by reference" do
        terracode
            var rule = gauss.productrule(&Q_1, &Q_2, Q_3)
            var s : double = 0.0
            for qr in rn.zip(&rule.x, &rule.w) do
                var x, w = qr
                s = s + w
            end
        end
        test tmath.isapprox(s, 60.0, 1e-14)
    end
   
end
