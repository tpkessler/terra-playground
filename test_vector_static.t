local vector = require("vector_static")
local io = terralib.includec("stdio.h")

local vectorDouble4 = vector(double, 4)
local vectorInt3 = vector(int64, 3)

terra main()
    var x = vectorDouble4.from(-1, 2, -3, 4) 
    var y = vectorDouble4.new()
    y:copy(&x)

    for i = 0, x:size() do
        io.printf("%g %g\n", x:get(i), y:get(i))
    end

    var z = vectorDouble4.from(4.45, 5, 3, 1)

    io.printf("%g\n", x:dot(&z))

    var a = vectorInt3.from(1, 2, 3)
    var b = vectorInt3.new()
    b:fill(2)

    for i = 0, a:size() do
        io.printf("%ld %ld\n", a:get(i), b:get(i))
    end
end

main()
