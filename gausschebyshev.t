local math = require('mathfuns')
local alloc = require('alloc')
local dvector = require('dvector')
local poly = require('poly')
local bessel = require("besselroots")
local err = require("assert")

local io = terralib.includec("stdio.h")

local size_t = uint32
local Allocator = alloc.Allocator
local dvec = dvector.DynamicVector(double)

local terra gausschebyshevt(alloc : Allocator, n : size_t)
    var x, w = dvec.new(&alloc, n), dvec.new(&alloc, n)
    for k = 1, n+1 do
        x(k-1) = math.cos((2. * k - 1.) * math.pi / (2. * n))
        w(k-1) = math.pi / n
    end
    return x, w
end

local terra gausschebyshevu(alloc : Allocator, n : size_t)
    var x, w = dvec.new(&alloc, n), dvec.new(&alloc, n)
    for k = 1, n+1 do
        x(k-1) = math.cos(k * math.pi / (n + 1.))
        w(k-1) = math.pi / (n + 1.) * math.pow(math.sin(k / (n + 1.) * math.pi), 2)
    end
    return x, w
end

local terra gausschebyshevv(alloc : Allocator, n : size_t)
    var x, w = dvec.new(&alloc, n), dvec.new(&alloc, n)
    for k = 1, n+1 do
        x(k-1) = math.cos((k - .5) * math.pi / (n + .5))
        w(k-1) = 2*math.pi / (n + .5) * math.pow(math.cos((k - .5) * math.pi / (2 * (n + .5))), 2)
    end
    return x, w
end

local terra gausschebyshevw(alloc : Allocator, n : size_t)
    var x, w = dvec.new(&alloc, n), dvec.new(&alloc, n)
    for k = 1, n+1 do
        x(k-1) = math.cos(k * math.pi / (n + .5))
        w(k-1) = 2*math.pi / (n + .5) * math.pow(math.sin(k * math.pi / (2. * (n + .5))), 2)
    end
    return x, w
end


return {
    chebyshev_t = gausschebyshevt,
    chebyshev_u = gausschebyshevu,
    chebyshev_v = gausschebyshevv,
    chebyshev_w = gausschebyshevw
}