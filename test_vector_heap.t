local vector = require("vector_heap")
local io = terralib.includec("stdio.h")

local VectorDouble = vector.VectorHeap(double)

terra main()
    var x = VectorDouble.from(1, 2, 3)
    x:push(10)

    io.printf("Initial state\n")
    for xx in x do
        io.printf("%g\n", xx)
    end

	io.printf("Perfom pop() operation on vector\n")
    x:pop()
	for xx in x do
		io.printf("%g\n", xx)
	end
	io.printf("Fill vector with constant values\n")
    x:fill(11)
	for xx in x do
		io.printf("%g\n", xx)
	end
	io.printf("Initialize vector from list\n")
    var y = VectorDouble.from(1, 2, 3)
	for yy in y do
		io.printf("%g\n", yy)
	end
	io.printf("Perform generic axpy\n")
    x:axpy(-2, &y)
	for xx in x do
		io.printf("%g\n", xx)
	end

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

    z:copy(&w)

    io.printf("Subview after copy\n")
    for zz in z do
        io.printf("%g\n", zz)
    end

    io.printf("Full vector after copy\n")
    for xx in x do
        io.printf("%g\n", xx)
    end

    var a = VectorDouble.zeroslike(x)
    var b = VectorDouble.like(a)
    b:fill(1)

    io.printf("Before swap\n")
    for i = 0, a:size() do
        io.printf("%g %g\n", a:get(i), b:get(i))
    end

    a:swap(&b)
    
    io.printf("After swap\n")
    for i = 0, a:size() do
        io.printf("%g %g\n", a:get(i), b:get(i))
    end

    a:scal(-3.14)

    io.printf("Scaled vector\n")
    for aa in a do
        io.printf("%g\n", aa)
    end

    io.printf("Inner product is %g\n", x:dot(&a))

    x:free()
    y:free()
    z:free()
    w:free()
    a:free()
    b:free()
end

main()
