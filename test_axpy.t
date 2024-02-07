local blas = require("axpy")
local mem = require("mem")
local C = terralib.includecstring[[
    #include <stdio.h>
]]

terra main()
    var n: int32 = 10
    var incx: int32 = 1
    var incy: int32 = 1
    escape
        for _, T in pairs({float, double}) do
            emit quote
                var x: &T = [&T](mem.new(sizeof(T) * n))
                var y: &T = [&T](mem.new(sizeof(T) * n))
                var alpha:T = T(2)

                for i: uint64 = 0, n do
                    @(x + i) = T(1)
                    @(y + i) = T(2)
                end

                C.printf("BLAS for type %s\n", [tostring(T)])
                blas.axpy(n, alpha, x, incx, y, incy)

                for i: uint64 = 0, n do
                    C.printf("%lu: %g\n", i, @(y + i))
                end
                C.printf("\n")

                mem.del(x)
                mem.del(y)
            end --quote
        end --for
    end --escape
end --main

main()
