require("terralibext")
local io = terralib.includec("stdio.h")
local interface = require "interface"
local alloc = require("alloc")
local err = require("assert")

local RangeBase = function(Range)
    --ranges support __for and __rshift
    --__for is a spcialization for each range
    --__rshift is a general implementation
    Range.metamethods.__rshift = macro(function(range, adapter)
        local self_type = range.tree.type
        local adapter_type = adapter.tree.type
        if self_type:isstruct() and self_type.metamethods.__for 
            and adapter_type:isstruct() 
        then
            local Adapter = adapter_type.generator
            local A = Adapter(self_type, adapter_type)
            return quote
                var a = A{range, adapter}
            in
                a
            end
        end
    end)

end

local struct linrange(RangeBase){
    a : int
    b : int
    current : int
}

terra linrange:__init()
    self.current = 0
end

terra linrange:first()
    return self.a
end

terra linrange:next()
    self.current = self.current + 1
end

linrange.metamethods.__for = function(iter,body)
    return quote
        var it = iter
        for i = it.a, it.b do
            [body(i)]
        end
    end
end


local EnumerateRange = function(Range, Adapter)

    local struct adapter(RangeBase){
        range : Range
        adap : Adapter
    }

    adapter.metamethods.__for = function(iter,body)
        return quote
            var i = 0
            for v in iter.range do
                [body(i,v)]
                i = i + 1
            end
        end
    end

    return adapter
end

local function newcombiner(Ranges, name)
    --create struct
    local combiner = terralib.types.newstruct(name)
    --add entries
    for i,Range in ipairs(Ranges) do
		combiner.entries:insert({field = tostring("_"..tostring(i-1)), type = Range})
	end
    --complete struct type
	combiner:complete()

    return combiner
end

local JoinRange = function(Ranges)

    local combirange = newcombiner(Ranges, "joiner")

    combirange.metamethods.__for = function(range,body)
        local D = #Ranges
        local stmts = terralib.newlist{}
        for k = 0, D-1 do
            local field = "_"..tostring(k)
            stmts:insert(quote
                for v in range.[field] do
                    [body(v)]
                end
            end)
        end
        return quote
            [stmts]
        end
    end

    return combirange
end

local ProductRange = function(Ranges)
  
    local combirange = newcombiner(Ranges, "product")

    --I've used explicit for loops, rather than recursion.
    --Recursion requires definition of the loop variables in
    --terms of symbols, which require a type. Maybe add as 
    --a type-trait?
    combirange.metamethods.__for = function(range,body)
        local D = #Ranges
        if D==1 then
            return quote
                for u in range._0 do
                    [body(u)]
                end
            end
        elseif D==2 then
            return quote
                for u_1 in range._1 do
                    for u_0 in range._0 do
                        [body(u_0, u_1)]
                    end
                end
            end
        elseif D==3 then
            return quote
                for u_2 in range._2 do
                    for u_1 in range._1 do
                        for u_0 in range._0 do
                            [body(u_0, u_1, u_2)]
                        end
                    end
                end
            end
        end
    end

    return combirange
end

local ZipRange = function(Ranges)
  
    local combirange = newcombiner(Ranges, "zip")

    --I've used explicit for loops, rather than recursion.
    --Recursion requires definition of the loop variables in
    --terms of symbols, which require a type. Maybe add as 
    --a type-trait?
    combirange.metamethods.__for = function(range,body)
        local D = #Ranges
        if D==1 then
            return quote
                for u in range._0 do
                    [body(u)]
                end
            end
        elseif D==2 then
            return quote
                for u_1 in range._1 do
                    for u_0 in range._0 do
                        [body(u_0, u_1)]
                    end
                end
            end
        elseif D==3 then
            return quote
                for u_2 in range._2 do
                    for u_1 in range._1 do
                        for u_0 in range._0 do
                            [body(u_0, u_1, u_2)]
                        end
                    end
                end
            end
        end
    end

    return combirange
end

local FilteredRange = function(Range, Function)

    local struct adapter(RangeBase){
        range : Range
        f : Function
    }

    adapter.metamethods.__for = function(iter,body)
        return quote
            for i in iter.range do
                if iter.f(i) then
                    [body(i)]
                end
            end
        end
    end

    return adapter
end

local TransformedRange = function(Range, Function)

    local struct adapter(RangeBase){
        range : Range
        f : Function
    }

    adapter.metamethods.__for = function(iter,body)
        return quote
            for i in iter.range do
                var j = iter.f(i)
                [body(j)]
            end
        end
    end

    return adapter
end

local TakeRange = function(Range)

    local struct adapter(RangeBase){
        range : Range
        take : int64
    }

    adapter.metamethods.__for = function(iter,body)
        return quote
            var count = 0
            for i in iter.range do
                if count==iter.take then
                    break
                end
                count = count + 1
                [body(i)]
            end
        end
    end

    return adapter
end

local DropRange = function(Range)

    local struct adapter(RangeBase){
        range : Range
        drop : int64
    }

    adapter.metamethods.__for = function(iter,body)
        return quote
            var count = 0
            for i in iter.range do
                count = count + 1
                if count>iter.drop then
                    [body(i)]
                end
            end
        end
    end

    return adapter
end


local TakeWhileRange = function(Range, Function)

    local struct adapter(RangeBase){
        range : Range
        pred : Function
    }

    adapter.metamethods.__for = function(iter,body)
        return quote
            for i in iter.range do
                if not iter.pred(i) then
                    break
                end
                [body(i)]
            end
        end
    end

    return adapter
end

local DropWhileRange = function(Range, Function)

    local struct adapter(RangeBase){
        range : Range
        pred : Function
    }

    adapter.metamethods.__for = function(iter,body)
        return quote
            var flag = true
            for i in iter.range do
                if flag and iter.pred(i)==false then
                    flag = false
                end
                if not flag then
                    [body(i)]
                end
            end
        end
    end

    return adapter
end

local adapter_lambda_factory = function(Adapter)
    local factory = macro(
        function(fun, ...)
            --get the captured variables
            local captures = terralib.newlist{...}
            --wrapper struct
            local struct wrapper{}
            wrapper.generator = Adapter
            --overloading the call operator - making 'wrapper' a function object
            wrapper.metamethods.__apply = macro(function(self, ...)
                local args = terralib.newlist{...}
                return `fun([args],[captures])
            end)
            --create and return wrapper object by reference
            return quote
                var lambda : wrapper
            in
                lambda
            end
        end)
    return factory
end

local adapter_view_factory = function(Adapter)
    local factory = macro(
        function(n)
            --wrapper struct
            local struct wrapper{
                size : int64
            }
            wrapper.generator = Adapter
            --enable casting to an integer from wrapper
            wrapper.metamethods.__cast = function(from, to, exp)
                if from:isstruct() and to:isintegral() then
                    return quote
                        var x = exp
                    in
                        [int64](x.size)
                    end
                end
            end

            --create and return wrapper object by reference
            return quote
                var v = wrapper{n}
            in
                v
            end
        end)
    return factory
end

local adapter_simple_factory = function(Adapter)
    local factory = macro(function()
        --wrapper struct
        local struct wrapper{
        }
        wrapper.generator = Adapter
        --create and return wrapper object by reference
        return quote
            var v = wrapper{}
        in
            v
        end
    end)
    return factory
end

local combiner_factory = function(Combiner)
    local combiner = macro(function(...)
        local ranges = terralib.newlist{...}
        local range_types = terralib.newlist{}
        for i,rn in ipairs(ranges) do
            range_types:insert(rn.tree.type)
        end
        local combirange = Combiner(range_types)
        return quote
            var range = combirange{[ranges]}
        in
            range
        end
    end)
    return combiner
end

--generate user api macro's for adapters
local transform = adapter_lambda_factory(TransformedRange)
local filter = adapter_lambda_factory(FilteredRange)
local take = adapter_view_factory(TakeRange)
local drop = adapter_view_factory(DropRange)
local take_while = adapter_lambda_factory(TakeWhileRange)
local drop_while = adapter_lambda_factory(DropWhileRange)
local enumerate = adapter_simple_factory(EnumerateRange)
--generate user api macro's for combi-ranges
local join = combiner_factory(JoinRange)
local product = combiner_factory(ProductRange)
local zip = combiner_factory(ZipRange)

terra test0()
    var range = linrange{0, 5}
    for i in range do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
--test0()

terra test1()
    var range = linrange{0, 5}
    var x = 2
    for i in range >> transform([terra(i : int, x : int) return x * i end], x) do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
--test1()

terra test2()
    var range = linrange{0, 5}
    var x = 0
    for i in range >> filter([terra(i : int, x : int) return i % 2 == x end], x) do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
--test2()


terra test3()
    var range = linrange{0, 5}
    var x = 0
    var y = 3
    var g = filter([terra(i : int, x : int) return i % 2 == x end], x)
    var h = transform([terra(i : int, y : int) return y * i end], y)
    for i in range >> g >> h do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
--test3()

terra test4()
    var x = 0
    var y = 3
    for i in linrange{0, 5} >> 
                filter([terra(i : int, x : int) return i % 2 == x end], x) >> 
                        transform([terra(i : int, y : int) return y * i end], y) 
    do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
--test4()

terra test5()
    for i in linrange{0, 10} >> take(4) do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
--test5()

terra test6()
    for i in linrange{0, 10} >> drop(4) do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
--test6()


terra test7()
    var x = 6
    for i in linrange{0, 10} >> take_while([terra(i : int, x : int) return i < x end], x) do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
--test7()

terra test8()
    var x = 6
    for i in linrange{0, 10} >> drop_while([terra(i : int, x : int) return i < x end], x) do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
--test8()


terra test9()
    for i,v in linrange{4, 10} >> enumerate() do
        io.printf("(%d, %d)\n", i, v)
    end
    io.printf("\n")
end
--test9()

terra test10()
    for v in join(linrange{1, 4}, linrange{4, 6}, linrange{6, 9}) do
        io.printf("%d\n", v)
    end
    io.printf("\n")
end
--test10()

terra test11()
    for x in product(linrange{1, 4}) do
        io.printf("(%d)\n", x)
    end
    io.printf("\n")
end
test11()

terra test12()
    for x,y in product(linrange{1, 4}, linrange{4, 6}) do
        io.printf("(%d, %d)\n", x, y)
    end
    io.printf("\n")
end
test12()

terra test13()
    for x,y,z in product(linrange{1, 4}, linrange{4, 6}, linrange{10, 14}) do
        io.printf("(%d, %d, %d)\n", x, y, z)
    end
    io.printf("\n")
end
test13()