local vector = require("vector")
local io = terralib.includec("stdio.h")

local VectorDouble = vector(double)

terra main()
    var x = VectorDouble.from(1, 2, 3)
    x:push(10)

    io.printf("Initial state\n")
    for xx in x do
        io.printf("%g\n", xx)
    end

    x:pop()
    x:fill(11)
    var y = VectorDouble.from(1, 2, 3)
    x:axpy(-2, y)

    io.printf("After push and pop and axpy\n")
    for xx in x do
        io.printf("%g\n", xx)
    end

    var z = x:subview(2, 1, 1)

    io.printf("Subview\n")
    for zz in z do
        io.printf("%g\n", zz)
    end

    var w = VectorDouble.like(z)
    w:set(0, -5)
    w:set(1, 7)

    z:copy(w)

    io.printf("Subview after copy\n")
    for zz in z do
        io.printf("%g\n", zz)
    end

    io.printf("Full vector after copy\n")
    for xx in x do
        io.printf("%g\n", xx)
    end

    x:free()
    y:free()
    w:free()
end

main()
