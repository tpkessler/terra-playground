local alloc = require("alloc")
local quad = require("halfrangehermite")
local tmath = require("mathfuns")
local lambda = require("lambda")
local range = require("range")

import "terratest/terratest"
import "terraform"

local integrate
terraform integrate(q, f)
    var it = q:getiterator()
    var x, w = it:getvalue()
    var res = [w.type](0)
    for xw in q do
        var x, w = xw
        res = res + w * f(x)
    end
    return res
end

local compute_moment
terraform compute_moment(q, k)
    var f = lambda.new([
                terra(x: double, k: int64)
                    return tmath.pow(x, k)
                end
            ], {k = k})
    return integrate(q, f)
end

local ref = terralib.constant(terralib.new(double[51], {
    0.5,0.3989422804014327,0.5,0.7978845608028654,1.5,3.1915382432114616,
    7.5,19.14922945926877,52.5,153.19383567415017,472.5,1531.9383567415016,
    5197.5,18383.26028089802,67567.5,257365.64393257227,1.0135125e6,4.1178503029211564e6,
    1.72297125e7,7.412130545258081e7,3.273645375e8,1.4824261090516162e9,6.8746552875e9,
    3.261337439913556e10,1.581170716125e11,7.827209855792534e11,3.9529267903125e12,
    2.0350745625060586e13,1.067290233384375e14,5.698208775016965e14,3.0951416768146875e15,
    1.7094626325050894e16,9.594939198125531e16,5.470280424016286e17,3.166329935381425e18,
    1.8598953441655374e19,1.1082154773834988e20,6.695623238995934e20,4.100397266318946e21,
    2.5443368308184548e22,1.5991549338643888e23,1.017734732327382e24,6.556535228843994e24,
    4.274485875775004e25,2.8193101484029176e26,1.8807737853410018e27,1.2686895667813128e28,
    8.65155941256861e28,5.962840963872171e29,4.152748518032932e30,2.9217920722973635e31
}))
local err = terralib.new(double[30])

for N = 1, 15 do
    testenv(N) "Quadrature exactness" do
        terracode
            var alloc: alloc.DefaultAllocator()
            var x, w = quad.halfrangehermite(&alloc, N)
            var q = range.zip(x, w)
            for k = 0, 2 * N do
                err[k] = tmath.abs(compute_moment(q, k) - ref[k]) / ref[k]
            end
        end
        for k = 0, 2 * N - 1 do
            test [err[k] < 1e-14]
        end
    end
end
