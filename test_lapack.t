local lapack = require("lapack")
local io = terralib.includec("stdio.h")

local terra print2x2(a: &double)
    io.printf("%g %g\n", a[0], a[1])
    io.printf("%g %g\n", a[2], a[3])
end

terra main()
    var a = arrayof(double, 1, 2, 3, 4)
    var q = arrayof(double, 1, 2)
    print2x2(&a[0])
    io.printf("\n")
    
    lapack.geqrf(lapack.ROW_MAJOR, 2, 2, &a[0], 2, &q[0])

    print2x2(&a[0])
    io.printf("%g %g\n", q[0], q[1])
end

main()
