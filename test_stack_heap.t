local Stack = require("stack_heap")
local Alloc = require("alloc")
local io = terralib.includec("stdio.h")

local stack = Stack.DynamicStack(double)


terra main()
    var alloc : Alloc.default
    var x = stack.new(&alloc, 2)
    x:set(0, 1.0)
    x:set(1, 2.0)
    io.printf("value of x[0] is: %f\n", x:get(0))
    io.printf("value of x[1] is: %f\n", x:get(1))
end

main()