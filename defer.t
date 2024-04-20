local alloc = require("alloc")
local io = terralib.includec("stdio.h")

USE_FREE = false

local new = macro(function(A)
    return quote
        var x = A:alloc(10)
        if USE_FREE then
            defer A:free(x)
        else
            defer io.printf("Empty free in new\n")
        end
    in
        x
    end
end)

local move = macro(function(x, A)
    return quote
        var y = @x
        @x = nil
        if USE_FREE then
            defer A:free(y)
        else
            defer io.printf("Empty free in move\n")
        end
    in
        y
    end
end)

local terra foo(A: alloc.Default)
    io.printf("In function foo\n")
    var x = [&int8](new(A))
    x[0] = @'t'
    return move(&x, A)
end

terra main()
    var A: alloc.Default
    var x = foo(A)
    io.printf("Outside function foo\n")
    io.printf("%c\n", x[0])
end

main()

terralib.saveobj("defer.o", {main = main}, {"-g"})
