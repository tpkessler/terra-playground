import "terratest/terratest"

local math = require("mathfuns")
local incbeta = require("incbeta")

math.isapprox = terra(a : double, b : double, atol : double)
    return math.abs(b-a) < atol
end

testenv "Regularized Incomplete Beta Function" do

    local atol = 1e-5

    test math.isapprox(incbeta(10., 10., .1), 0.00000, atol)
    test math.isapprox(incbeta(10., 10., .3), 0.03255, atol)
    test math.isapprox(incbeta(10., 10., .5), 0.50000, atol)
    test math.isapprox(incbeta(10., 10., .7), 0.96744, atol)
    test math.isapprox(incbeta(10., 10.,  1.), 1.00000, atol)

    test math.isapprox(incbeta(15, 10, .5), 0.15373, atol)
    test math.isapprox(incbeta(15, 10, .6), 0.48908, atol)

    test math.isapprox(incbeta(10, 15, .5), 0.84627, atol)
    test math.isapprox(incbeta(10, 15, .6), 0.97834, atol)

    test math.isapprox(incbeta(20, 20, .4), 0.10206, atol)
    test math.isapprox(incbeta(40, 40, .4), 0.03581, atol)
    test math.isapprox(incbeta(40, 40, .7), 0.99990, atol)
end