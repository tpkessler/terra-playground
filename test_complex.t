local C = terralib.includecstring[[
    #include <stdio.h>
]]

local complex = require("complex")

local complexFloat = complex(float)
local complexDouble = complex(double)

terra main()
    var x: complexDouble = {1, 2}
    C.printf("%e %e\n", x.re, x.im) 
    C.printf("%zu\n", sizeof(complexFloat))
    C.printf("%zu\n", sizeof(complexDouble))
    var p = [&double](&x)
    C.printf("%e %e\n", @p, @(p + 1))

    var y: complexDouble = x * x
    C.printf("%e %e\n", y.re, y.im)

    var z: complexDouble = x + x
    C.printf("%e %e\n", z.re, z.im)

    var w: complexDouble = x * x - x
    C.printf("%e %e\n", w.re, w.im)

    var a: complexDouble = x * x / x
    C.printf("%e %e\n", a.re, a.im)
end

main()
