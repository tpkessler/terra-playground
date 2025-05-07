local newton = require("newton")
local sarray = require("sarray")
local tmath = require("tmath")
local nfloat = require("nfloat")
local complex = require("complex")

import "terratest/terratest"
import "terraform"

local float256 = nfloat.FixedFloat(256)
local float4096 = nfloat.FixedFloat(4096)
local complexDouble = complex.complex(double)
local tols = {
    [float] = `1e-5f,
    [double] = `1e-14,
    -- Currently not supported in sarray
    -- [complexDouble] = `1e-14,
    [float256] = "1e-32",
    [float4096] = "1e-1200",
}

testenv "Scalar problems" do
    for T, reftol in pairs(tols) do
        testset(T) "Square roots" do
            local S = sarray.StaticVector(T, 1)
            local Ts = T == complexDouble and double or T
            local N = 2
            local sqrtN = math.sqrt(2)
            local terraform residual(x: &S, r: &S)
                r(0) = x(0) * x(0) - N
            end
            local terraform invjacobian(x: &S, b: &S, r: &S)
                r(0) = b(0) / (2 * x(0))
            end
            terracode
                var x = S.new()
                var ref: T = tmath.sqrt([Ts](N))
                var kmax = 100
                var tol: Ts = [reftol]
                var lambda0: Ts = 1
                var lambdamin: Ts = [Ts]([reftol]) / 10
                x(0) = 1
                newton.affine(residual, invjacobian, &x, tol, kmax, lambda0, lambdamin)
            end
            test tmath.isapprox(x(0), ref, 10 * [T](tol) * ref)
        end
    end

end
