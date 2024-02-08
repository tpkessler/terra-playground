local C = terralib.includecstring[[
    #include <stdio.h>
]]

local complex = require("complex")

local complexFloat, If = unpack(complex(float))
local complexDouble, I = unpack(complex(double))

terra main()
    var x = complexDouble {1, 2}
    C.printf("Testing type %s\n", [tostring(complexDouble)])
    C.printf("%e %e\n", x.re, x.im) 
    C.printf("Size of %s is %zu\n", [tostring(complexFloat)],
                                    sizeof(complexFloat))
    C.printf("Size of %s is %zu\n", [tostring(complexDouble)],
                                    sizeof(complexDouble))
    var p = [&double](&x)
    C.printf("%e %e\n", @p, @(p + 1))

    var y = x * x
    C.printf("%e %e\n", y.re, y.im)

    var z = x + x
    C.printf("%e %e\n", z.re, z.im)

    var w = x * x - x
    C.printf("%e %e\n", w.re, w.im)

    var a = x * x / x
    C.printf("%e %e\n", a.re, a.im)

    C.printf("Testing implicit cast\n")
    var c = 2 * x + y
    C.printf("%e %e\n", c.re, c.im)

    C.printf("Testing complex unit\n")
    var d = -2 * I
    C.printf("%e %e\n", d.re, d.im)
end

main()
