local io = terralib.includec("stdio.h")

local alloc = require("alloc")
local err = require("assert")


local struct linrange{
    a : int
    b : int
}

linrange.metamethods.__for = function(iter,body)
    return quote
        var it = iter
        for i = it.a, it.b do
            [body(i)]
        end
    end
end

terra main()
    var range = linrange{0, 5}
    for i in range do
        io.printf("%d\n", i)
    end
end
main()


