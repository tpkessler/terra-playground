local io = terralib.includec("stdio.h")

local lambda = macro(
    function(fun, ...)
        --get the captured variables
        local captures = {...}
        --wrapper struct
        local struct lambda {}
        --overloading the call operator - making 'lambda' a function object
        lambda.metamethods.__apply = macro(function(self, ...)
            local args = terralib.newlist{...}
            return `fun([args],[captures])
        end)
        lambda.returntype = fun.tree.type.type.returntype
        --create and return lambda object by value
        return quote
            var f = lambda{}
        in
            f
        end
    end
)


local Linrange = function(T)

    local struct linrange{
        a : T
        b : T
    }

    terra linrange:size()
        return self.b - self.a
    end

    linrange.metamethods.__for = function(self, body)
        return quote
            var iter = self
            for i = iter.a, iter.b do
                [body(i)]
            end
        end
    end

    return linrange
end

local linrange = Linrange(int)

terra test1()
    io.printf("lambda \n")
    var range = linrange{0,4}
    var x = 3
    var g = lambda([terra(i : int, x : int) return x * i end], 2)
    io.printf("%d\n", g(2))

    for r in range do
        io.printf("%d\n", r)
    end
end
test1()