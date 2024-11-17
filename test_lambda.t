import "terratest/terratest"

local lambda = require("lambda")

testenv "Single argument, no capture" do
    local A = lambda.lambda(int -> int)
    terracode
        var a = A.new([terra(x: int) return x + 1 end])
        var x = 10
        var yref = 11
    end
    testset "Direct call" do
        terracode
            var yres = a(x)
        end

        test yref == yres
    end

    testset "Indirect call via interface" do
        terracode
            var ac = [A](&a)
            var yres = ac(x)
        end

        test yref == yres
    end
end

testenv "Single argument with capture" do
    local A = lambda.lambda(int -> int, struct {y: int})
    terracode
        var yref = 3
        var a = A.new([terra(x: int, y: int) return x * y end], yref)
        var x = 12
        var zref = 36
    end
    testset "Direct call" do
        terracode
            var zres = a(x)
            var yres = a.y
        end

        test zref == zres
        test yref == yres
    end

    testset "Indirect call via interface" do
        terracode
            var ac = [A](&a)
            var zres = ac(x)
            var yres = ac.y
        end

        test zref == zres
        test yref == yres
    end
end

testenv "Multiple arguments with single capture" do
    local A = lambda.lambda({int, double} -> double, struct {y: int})
    terracode
        var yref = 3
        var a = A.new(
                    [terra(x: int, b: double, y: int) return b * x + y end],
                    yref
                )
        var x = 12
        var b = 0.5
        var zref = 9.0 
    end
    testset "Direct call" do
        terracode
            var zres = a(x, b)
            var yres = a.y
        end

        test zref == zres
        test yref == yres
    end

    testset "Indirect call via interface" do
        terracode
            var ac = [A](&a)
            var zres = ac(x, b)
            var yres = ac.y
        end

        test zref == zres
        test yref == yres
    end
end

testenv "Multiple arguments with capture" do
    local A = lambda.lambda({int, double} -> double, struct {y: int, c: bool})
    terracode
        var yref = 3
        var cref = false
        var a = A.new(
                    [
                        terra(x: int, b: double, y: int, c: bool)
                            return b * x + y
                        end
                    ],
                    yref, cref
                )
        var x = 12
        var b = 0.5
        var zref = 9.0 
    end
    testset "Direct call" do
        terracode
            var zres = a(x, b)
            var yres = a.y
            var cres = a.c
        end

        test zref == zres
        test yref == yres
        test cref == cres
    end

    testset "Indirect call via interface" do
        terracode
            var ac = [A](&a)
            var zres = ac(x, b)
            var yres = ac.y
            var cres = ac.c
        end

        test zref == zres
        test yref == yres
        test cref == cres
    end
end


local LAMBDIFY = function(sig, func)
    return macro(function(...)
        local args = {...}
        local lambda = {}
        for i = 1, #sig do
            lambda[i] = args[i]
        end
        local func_args = {}
        for i = #sig + 1, #args do
            func_args[i - #sig] = args[i]
        end
        local impl = func(unpack(lambda))
        impl:printpretty()
        return `impl([func_args])
    end)
end

local L1 = double
local L2 = double
local prod = LAMBDIFY(
    {L1, L2},
    function(f, g)
        return terra(x: double, y: int)
            return f(x) * g(y)
        end
    end
)

local io = terralib.includec("stdio.h")
terra main()
    var res = prod([terra(x: double) return x end], [terra(y: int) return y end], 2, 3)
    io.printf("res = %g\n", res)
end
main()
