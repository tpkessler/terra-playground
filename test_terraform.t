import "terraform"

local io = terralib.includec("stdio.h")
local concept = require("concept")

import "terratest/terratest"

local Real = concept.Real
local Float = concept.Float

testenv "terraforming free functions" do


    testset "method dispatch" do
        terraform foo(a : T, b : T) where {T : Real}
            return a * b
        end
        terraform foo(a : int, b : T) where {T : Real}
            return a * b + 1
        end
        terraform foo(a : T, b : int) where {T : Real}
            return a * b + 2
        end
        terraform foo(a : int, b : int)
            return a * b + 3
        end
        --typical use-case in dispatch
        test foo(1., 2.) == 2.0
        test foo(1, 2.) == 3.0
        test foo(1., 2) == 4.0
        test foo(1, 2) == 5.0
    end

    testset "nearly ambiguous calls" do
        --foo<T>
        terraform foo(a : T, b : T) where {T : Float}
            return a * b
        end
        --foo<T1,T2>
        terraform foo(a : T1, b : T2) where {T1 : Float, T2 : Float}
            return a * b + 1
        end
        --both of the following calls satisfy the concept dispatch 
        --checks on all arguments. 
        test foo(1., 2.) == 2.0 --calling foo<T> and foo<T1,T2> are both valid. However,
        --foo<T> is considered to be more specialized, so we pick this method.
        test foo(float(1), 2.) == 3.0 --calling foo<T> would lead to a cast, which is 
        --not allowed, so we call foo<T1,T2>
    end

    testset "concrete types" do
        terraform foo(a : double, b : double)
            return a * b + 2
        end

        terraform foo(a : float, b : double)
            return a * b + 3
        end
        test foo(1., 2.) == 4.0
        test foo(float(1), 2.) == 5.0
    end    

    testset "nested namespaces" do
        local ns = {}
        ns.Float = Float
        ns.bar = {}
        ns.bar.Float = Float
        --foo<T>
        terraform ns.bar.foo(a : T, b : T) where {T : ns.bar.Float}
            return a * b
        end
        --foo<T1,T2>
        terraform ns.bar.foo(a : T1, b : T2) where {T1 : ns.Float, T2 : ns.bar.Float}
            return a * b + 1
        end
        test ns.bar.foo(1., 2.) == 2.0
        test ns.bar.foo(float(1), 2.) == 3.0 
    end

end
