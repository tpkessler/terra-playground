local lapack = require("lapack")
local io = terralib.includec("stdio.h")
local complex = require("complex")

local complexDouble, I = unpack(complex(double))

local terra print2x2(a: &double)
    io.printf("%g %g\n", a[0], a[1])
    io.printf("%g %g\n", a[2], a[3])
end

terra main()
    var a = arrayof(double, 1, 2, 3, 4)
    var q = arrayof(double, 1, 2)
    print2x2(&a[0])
    io.printf("\n")
    
    var info = lapack.geqrf(lapack.ROW_MAJOR, 2, 2, &a[0], 2, &q[0])

    io.printf("QR finished with info %d\n", info)

    print2x2(&a[0])
    io.printf("%g %g\n", q[0], q[1])

    var ac = 1 + I
    var qc = 0 * I

    info = lapack.geqrf(lapack.ROW_MAJOR, 1, 1, &ac, 1, &qc)

    io.printf("Complex QR finished with info %d\n", info)

    io.printf("%g + I %g\n", ac:real(), ac:imag())
    io.printf("%g + I %g\n", qc:real(), qc:imag())
end

main()
