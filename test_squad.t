local geo = require("geometry")
local squad = require("squad")
local tmath = require('mathfuns')

import "terratest/terratest"

local T = double

testenv "singular quadrature - smooth kernel" do

    local I, J = geo.Interval.new(0,1), geo.Interval.new(1,2)

    local kernel = terra(x : T[3], y : T[3], alpha : double)
        return 1.0
    end

    --definition of a kernel type
    local Kernel = lambda.lambda({T[3], T[3]} -> double, struct {alpha: double})
    --create lambda
    terracode
        var kernel = Kernel.new([terra(x : T[3], y : T[3], alpha : double) return 1.0 end], 1.0)
    end

    --x-coordinates from mapping to physical (curved) space
    terra squad.xcoord(xhat : T[3], yhat : T[3])
        return xhat
    end
    --y-coordinates from mapping to physical (curved) space
    terra squad.ycoord(xhat : T[3], yhat : T[3])
        return yhat
    end
 
    testset "3D intersection" do
        local integrand = squad.Integrand{
            domain_a=geo.Hypercube.new(I, I, I), 
            domain_b=geo.Hypercube.new(I, I, I)
        }
        terracode
            var G : integrand
            var s = G:integrate(&kernel, 4)
        end
        test tmath.isapprox(s, 1.0, 1e-12)
    end

    testset "2D intersection" do
        local integrand = squad.Integrand{
            domain_a=geo.Hypercube.new(I, I, I), 
            domain_b=geo.Hypercube.new(J, I, I)
        }
        terracode
            var G : integrand
            var s = G:integrate(&kernel, 4)
        end
        test tmath.isapprox(s, 1.0, 1e-12)
    end

    testset "1D intersection" do
        local integrand = squad.Integrand{
            domain_a=geo.Hypercube.new(I, I, I), 
            domain_b=geo.Hypercube.new(J, J, I)
        }
        terracode
            var G : integrand
            var s = G:integrate(&kernel, 4)
        end
        test tmath.isapprox(s, 1.0, 1e-12)
    end

    testset "0D intersection" do
        local integrand = squad.Integrand{
            domain_a=geo.Hypercube.new(I, I, I), 
            domain_b=geo.Hypercube.new(J, J, J)
        }
        terracode
            var G : integrand
            var s = G:integrate(&kernel, 4)
        end
        test tmath.isapprox(s, 1.0, 1e-12)
    end

    local integrand = squad.Integrand{
        domain_a=geo.Hypercube.new(geo.Interval.new(0,2), I, I), 
        domain_b=geo.Hypercube.new(geo.Interval.new(2,3), I, I)
    }

    local f1 = terra(x : T[3], y : T[3], alpha : T) return 1.0 end
    local f2 = terra(x : T[3], y : T[3], alpha : T) return x[0] end
    local f3 = terra(x : T[3], y : T[3], alpha : T) return x[1] end
    local f4 = terra(x : T[3], y : T[3], alpha : T) return x[2] end

    testset "reproduction of moments" do
        terracode
            var G : integrand
            var s = { 
                G:integrate(Kernel.new([f1], 1.0), 4),
                G:integrate(Kernel.new([f2], 1.0), 4),
                G:integrate(Kernel.new([f3], 1.0), 4),
                G:integrate(Kernel.new([f4], 1.0), 4)
            }
        end
        test tmath.isapprox(s._0, 2.0, 1e-12)
        test tmath.isapprox(s._1, 2.0, 1e-12)
        test tmath.isapprox(s._2, 1.0, 1e-12)
        test tmath.isapprox(s._3, 1.0, 1e-12)
    end

end
--[[
testenv "singular quadrature - rough kernel" do

    --values computed to double precision
    local G = {
        0.4665733572942235, 
        2.0807459152202297, 
        8.332275230772728, 
        28.40088713015304
    }

    local kernel = terra(x : T[3], y : T[3], alpha : double)
        var s = 0.0
        for k=0,3 do
            s = s + tmath.pow(y[k]-x[k], 2)
        end
        s = tmath.sqrt(s)
        return tmath.pow(s, alpha)
    end

    local D = 3
    local I, J = geo.Interval.new(0,1), geo.Interval.new(1,2)

    for K=0,3 do
        local Js = {I, I, I}
        for k=K+1,3 do
            Js[k] = J
        end
        local A = geo.Hypercube.new(I, I, I)
        local B = geo.Hypercube.new(unpack(Js))
        local alpha = -2 * D + K + (1.0 / math.pi)
        local precomputedval = G[K+1]

        testset(K) "3D intersection" do
            local integrand = squad.Integrand{
                domain_a=A, 
                domain_b=B
            }
            terracode
                var G : integrand
                var s = G:integrate(squad.kernel_t{kernel, {alpha}}, 8)
            end
            test tmath.isapprox(s, precomputedval, 1e-8)
        end
    end
end
--]]