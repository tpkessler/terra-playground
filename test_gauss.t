-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"
local io = terralib.includec('stdio.h')
local Alloc = require('alloc')
local gauss = require("gauss")
local math = require("mathfuns")
local vector = require("dvector")
local poly = require("poly")
local rn = require("range")

local Allocator = Alloc.Allocator
local DefaultAllocator =  Alloc.DefaultAllocator()
local dvec = vector.DynamicVector(double)

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

--[[
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
            test x:size() == N and w:size() == N
            test math.isapprox(w:sum(), 2.0, 1e-13)
            test math.isapprox(s, S, 1e-13)
        end
    end

end

testenv "gauss Chebyshev quadrature" do

    local poly2 = poly.Polynomial(double, 3)
    local poly3 = poly.Polynomial(double, 4)
    local N = 10

    terracode
        var alloc : DefaultAllocator
        var p2 = poly2.from(0.0,0.0,1.0)
        var p3 = poly3.from(0.0,0.0,0.0,1.0)
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
            test x:size() == N and w:size() == N
            test math.isapprox(s2, math.pi/2., 1e-14)
            test math.isapprox(s3, 0., 1e-14)
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
            test x:size() == N and w:size() == N
            test math.isapprox(s2, math.pi/8., 1e-14)
            test math.isapprox(s3, 0., 1e-14)
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
            test x:size() == N and w:size() == N
            test math.isapprox(s2, math.pi/2., 1e-14)
            test math.isapprox(s3, 3.*math.pi/8., 1e-14)
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
            test x:size() == N and w:size() == N
            test math.isapprox(s2, math.pi/2., 1e-14)
            test math.isapprox(s3, -3.*math.pi/8., 1e-14)
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
            test x:size() == N and w:size() == N
            test math.isapprox(xref, x, 1e-13)
            test math.isapprox(wref, w, 1e-13)
        end

        testset(N) "reproduce gauss-Chebyshev of the 1st kind" do
            terracode
                var x, w = gauss.jacobi(&alloc, N, -0.5, -0.5)
                var xref, wref = gauss.chebyshev_t(&alloc, N)
            end
            test x:size() == N and w:size() == N
            test math.isapprox(xref, x, 1e-13)
            test math.isapprox(wref, w, 1e-13)
        end

        testset(N) "reproduce gauss-Chebyshev of the 2st kind" do
            terracode
                var x, w = gauss.jacobi(&alloc, N, 0.5, 0.5)
                var xref, wref = gauss.chebyshev_u(&alloc, N)
            end
            test x:size() == N and w:size() == N
            test math.isapprox(xref, x, 1e-13)
            test math.isapprox(wref, w, 1e-13)
        end

        testset(N) "reproduce gauss-Chebyshev of the 3rd kind" do
            terracode
                var x, w = gauss.jacobi(&alloc, N, -0.5, 0.5)
                var xref, wref = gauss.chebyshev_v(&alloc, N)
            end
            test x:size() == N and w:size() == N
            test math.isapprox(xref, x, 1e-13)
            test math.isapprox(wref, w, 1e-13)
        end

        testset(N) "reproduce gauss-Chebyshev of the 4rd kind" do
            terracode
                var x, w = gauss.jacobi(&alloc, N, 0.5, -0.5)
                var xref, wref = gauss.chebyshev_w(&alloc, N)
            end
            test x:size() == N and w:size() == N
            test math.isapprox(xref, x, 1e-13)
            test math.isapprox(wref, w, 1e-13)
        end
    end

    testset "n = 1" do
        terracode
            var a, b = 1.0, 2.0
            var x, w = gauss.jacobi(&alloc, 1, a, b)
        end
        test x:size() == 1 and w:size() == 1
        test math.isapprox(x(0), (b - a) / (a + b + 2), 1e-13)
        test math.isapprox(w(0), 1.3333333333333333, 1e-13)
    end

    testset "a specific n = 10" do
        terracode
            var x, w = gauss.jacobi(&alloc, 10, 0.2, -1./30.)
        end
        test x:size() == 10 and w:size() == 10
        test math.isapprox(x(6), 0.41467011760532446, 1e-13)
        test math.isapprox(w(2), 0.24824523988590236, 1e-13)
    end

    testset "a specific n = 42" do
        terracode
            var x, w = gauss.jacobi(&alloc, 42, -.1, .3)
        end
        test x:size() == 42 and w:size() == 42
        test math.isapprox(x(36), 0.912883347814032, 1e-13)
        test math.isapprox(w(36), 0.046661910947553, 1e-13)
    end

end
--]]

local struct interval{
    a : double
    b : double
}

testenv "API" do

    terracode
        var alloc : DefaultAllocator
    end

    testset "legendre - without interval" do
        terracode
            var x, w = gauss.rule("legendre", &alloc, 3)
        end
        test x:size() == 3 and w:size() == 3
    end
    
    testset "legendre - with interval" do
        terracode
            var x,w = gauss.rule("legendre", interval{a=1.0, b=3.0}, &alloc, 3)
        end
        test x:size() == 3 and w:size() == 3
        test math.isapprox(w:sum(), 2.0, 1e-13)
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
            var x,w = gauss.rule("legendre", interval{a=1.0, b=4.0}, &alloc, N)
            var s = 0.0
            for qr in rn.zip(x,w) do
                var xx, ww = qr
                s = s + ww * p(xx)
            end
        end
        test x:size() == N and w:size() == N
        test math.isapprox(w:sum(), 3.0, 1e-13)
        test math.isapprox(s, 5997.0 / 20.0, 1e-13)
    end

    testset "tensor-product rules" do
        terracode
            var Q_1 = gauss.rule("legendre", interval{a=0.0, b=3.0}, &alloc, 3)
            var Q_2 = gauss.rule("legendre", interval{a=1.0, b=5.0}, &alloc, 4)
            var s : double = 0.0
            for qr in rn.zip(
                rn.product(&Q_1.x, &Q_2.x), 
                rn.product(&Q_1.w, &Q_2.w) >> rn.transform([terra(w : &tuple(double,double)) return w._0 * w._1 end])
            ) do
                var x, w = qr
                s = s + w
            end
        end
        test math.isapprox(s, 12.0, 1e-14)
    end
   
end