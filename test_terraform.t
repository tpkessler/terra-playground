import "terraform"

local io = terralib.includec("stdio.h")
local concept = require("concept")

import "terratest/terratest"

local Float = concept.Float
local Integer = concept.Integer

local ns = {}
ns.bar = {}
ns.bar.Float = Float


testenv "terraforming free functions" do

    terraform foo(a : T, b : double, c : T) where {T}
        return a * b * c
    end
    --{Float, double, Float}, {1,2,1} = {Float, double}

    test foo(1.0, 2.0, 3.0)==6

    terraform foo(a : T1, b : double, c : T2) where {T1 : Float, T2 : Float}
        return a * b * c + 1
    end
    --{Float, double, Float}, {1,2,3} = {Float, double, Float}

    test foo(1.0, 2.0, 3.0)==7

    terraform foo(a : double, b : double, c : double)
        return a * b * c + 2
    end

    test foo(1.0, 2.0, 3.0)==8

end