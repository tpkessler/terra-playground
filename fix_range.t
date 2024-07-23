local io = terralib.includec("stdio.h")

local lambda = macro(terralib.memoize(
function(fun, ...)
    --get the captured variables
    local captures = {...}
    --wrapper struct
    local lambda = terralib.types.newstruct("lambda")
    --add captured variable types as entries to the wrapper struct
    for i, v in ipairs(captures) do
		lambda.entries:insert({field = "_"..tostring(i-1), type = v.tree.type})
	end
	lambda:complete()
    --overloading the call operator - making 'lambda' a function object
    lambda.metamethods.__apply = macro(terralib.memoize(function(self, ...)
        local args = terralib.newlist{...}
        local capt = terralib.newlist()
        for i,v in ipairs(self.tree.type.entries) do
            local field = "_"..tostring(i-1)
            capt:insert(quote in self.[field] end)
        end
        return `fun([args], [capt])
    end))
    --maybe the return-type is usefull in further metaprogramming, so add it here:
    lambda.returntype = fun.tree.type.type.returntype
    --create and return lambda object by value
    return quote
        var f = lambda{[captures]}
    in
        f
    end
end))

terra main()
    io.printf("evaluating lambda \n")
    var x = 2
    var y = 3
    var p = lambda([terra(i : int, x : int, y : int) return x * y * i*i end], x, y) 
    io.printf("%d\n", p(2))
end
main()