local tree = require("tree")
local alloc = require("alloc")
local io = terralib.includec("stdio.h")

local DefaultAllocator = alloc.DefaultAllocator()
local TreeDouble = tree.Tree(double)

terra main()
    var alloc: DefaultAllocator
    var t = TreeDouble.new(&alloc, 0.0, 4)
    for i = 0, 4 do
        t.son(i) = TreeDouble.new(&alloc, i + 1, 0)
    end

    for x in t do
        io.printf("%g\n", x)
    end
end
main()
