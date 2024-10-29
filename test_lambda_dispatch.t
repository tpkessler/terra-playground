import "terraform"
local io = terralib.includec("stdio.h")
--local lambda = require("lambda")
local base = require("base")


local Bar = terralib.memoize(function(T)

    local struct bar{
        x : T
    }
    base.AbstractBase(bar)

    terraform bar:eval(x : double, y : double)
        return 1.0
    end

    return bar
end)

print(type(Bar(double)))

--local Kernel = lambda.lambda({double} -> double, struct {y: double})
local mybar = Bar(double)

terra main()
    --var f = Kernel.new([terra(x : double, y : double) return x * y end], 2.0)
    var x = mybar{2.0}
    --var y = x:eval(&f, 2.0)
end
main()
