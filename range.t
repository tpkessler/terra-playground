local io = terralib.includec("stdio.h")
local interface = require("interface")
local err = require("assert")

local size_t = uint64

local Stacker = terralib.memoize(function(T, I)
    I = I or uint64
    return interface.Interface:new{
            size = {} -> uint64,
            set = {I, T} -> {},
            get = {I} -> {T}
        }
end)

local RangeBase = function(Range, T)

    --set the element type of the range
    Range.eltype = T

    --ranges support __for and __rshift
    --__for is a spcialization for each range
    --__rshift is a general implementation
    Range.metamethods.__rshift = macro(function(self, adapter)
        local self_type = self.tree.type
        local adapter_type = adapter.tree.type
        if self_type:isstruct() and self_type.metamethods.__for 
            and adapter_type:isstruct() 
        then
            local Adapter = adapter_type.generator
            local A = Adapter(self_type, adapter_type)
            return quote
                var newrange = A{self, adapter}
            in
                newrange
            end
        end
    end)

    Range.metamethods.__for = function(self,body)
        return quote
            var iter = self
            var state, value = iter:getfirst()
            while not iter:islast(state, value) do
                [body(value)]
                value = iter:getnext(state)
            end
        end
    end

end

--convenience macro that yields the next value that satisfies the predicate
local __getnextvalue_that_satisfies_predicate = macro(function(self, state, value, condition)
    local condition = condition or false
    return quote
        while self.predicate(value)==condition do
            if self.range:islast(state) then break end
            value = self.range:getnext(state)
        end
    end
end)


local Linrange = function(T)

    local struct linrange{
        a : T
        b : T
    }

    terra linrange:size()
        return self.b - self.a
    end

    linrange.methods.getfirst = macro(function(self)
        return quote 
        in
            0, self.a
        end
    end)

    linrange.methods.getnext = macro(function(self, state)
        return quote 
            state = state + 1
            var value = self.a + state
        in
            value
        end
    end)

    linrange.methods.islast = macro(function(self, state, value)
        return quote 
            var terminate = (state == self:size())
        in
            terminate
        end
    end)

    --add metamethods
    RangeBase(linrange, T)

    --collect requires only the 'Stacker' interface
    local S = Stacker(T)
    terra linrange:collect(container : S)
        var count = 0
        for v in self do
            --boundschecking is done in the set method (implemented 
            --in block for dynamic datastructures)
            container:set(count, v)
            count = count + 1
        end
    end

    return linrange
end

local FilteredRange = function(Range, Function)

    --check that function is a predicate
    assert(Function.returntype == bool)

    local struct adapter{
        range : Range
        predicate : Function
    }

    adapter.methods.getfirst = macro(function(self)
        return quote
            var state, value = self.range:getfirst()
            __getnextvalue_that_satisfies_predicate(self, state, value)
        in
            state, value
        end
    end)

    adapter.methods.getnext = macro(function(self, state)
        return quote
            var value = self.range:getnext(state)
            __getnextvalue_that_satisfies_predicate(self, state, value)
        in
            value
        end
    end)

    adapter.methods.islast = macro(function(self, state, value)
        return quote 
            var terminate = self.range:islast(state)
        in
            terminate
        end
    end)

    --add metamethods
    local T = Range.eltype
    RangeBase(adapter, T)
    
    return adapter
end

local TransformedRange = function(Range, Function)

    local struct adapter{
        range : Range
        f : Function
    }

    adapter.methods.getfirst = macro(function(self)
        return quote
            var state, value = self.range:getfirst()
            var newvalue = self.f(value)
        in
            state, newvalue
        end
    end)

    adapter.methods.getnext = macro(function(self, state)
        return quote
            var value = self.range:getnext(state)
            var newvalue = self.f(value)
        in
            newvalue
        end
    end)

    adapter.methods.islast = macro(function(self, state, value)
        return quote 
            var terminate = self.range:islast(state)
        in
            terminate
        end
    end)

    --add metamethods
    local T = Function.returntype
    RangeBase(adapter, T)

    return adapter
end

local TakeRange = function(Range)

    local struct adapter{
        range : Range
        take : int64
    }

    adapter.methods.getfirst = macro(function(self)
        return `self.range:getfirst()
    end)

    adapter.methods.getnext = macro(function(self, state)
        return quote
            var value = self.range:getnext(state)
            self.take = self.take - 1
        in
            value
        end
    end)

    adapter.methods.islast = macro(function(self, state, value)
        return quote 
            var terminate = (self.take == 0) or self.range:islast(state)
        in
            terminate
        end
    end)

    --add metamethods
    local T = Range.eltype
    RangeBase(adapter, T)

    return adapter
end

local DropRange = function(Range)

    local struct adapter{
        range : Range
        drop : int64
    }

    adapter.methods.getfirst = macro(function(self)
        return quote
            var state, value = self.range:getfirst()
            var drop = self.drop
            for k = 0, drop do
                value = self.range:getnext(state)
                self.drop = self.drop - 1
            end
        in
            state, value
        end
    end)

    adapter.methods.getnext = macro(function(self, state)
        return quote 
            var value = self.range:getnext(state)
        in
            value
        end
    end)

    adapter.methods.islast = macro(function(self, state, value)
        return quote 
            var terminate = self.range:islast(state)
        in
            terminate
        end
    end)

    --add metamethods
    local T = Range.eltype
    RangeBase(adapter, T)

    return adapter
end


local TakeWhileRange = function(Range, Function)

    --check that function is a predicate
    assert(Function.returntype == bool)

    local struct adapter(RangeBase){
        range : Range
        predicate : Function
    }

    adapter.methods.getfirst = macro(function(self)
        return `self.range:getfirst()
    end)

    adapter.methods.getnext = macro(function(self, state)
        return `self.range:getnext(state)
    end)

    adapter.methods.islast = macro(function(self, state, value)
        return quote 
            var terminate = self.predicate(value)==false
        in
            terminate
        end
    end)

    --add metamethods
    local T = Range.eltype
    RangeBase(adapter, T)

    return adapter
end

local DropWhileRange = function(Range, Function)

    local struct adapter{
        range : Range
        predicate : Function
    }

    adapter.methods.getfirst = macro(function(self)
        return quote
            var state, value = self.range:getfirst()
            __getnextvalue_that_satisfies_predicate(self, state, value, true)
        in
            state, value
        end
    end)

    adapter.methods.getnext = macro(function(self, state)
        return `self.range:getnext(state)
    end)

    adapter.methods.islast = macro(function(self, state, value)
        return quote 
            var terminate = self.range:islast(state)
        in
            terminate
        end
    end)

    --add metamethods
    local T = Range.eltype
    RangeBase(adapter, T)

    return adapter
end

local adapter_lambda_factory = function(Adapter)
    local factory = macro(
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
            lambda.generator = Adapter
            lambda.returntype = fun.tree.type.type.returntype
            --create and return lambda object by value
            return quote
                var f = lambda{}
            in
                f
            end
        end)
    return factory
end

local adapter_view_factory = function(Adapter)
    local factory = macro(
        function(n)
            --wrapper struct
            local struct view{
                size : int64
            }
            view.generator = Adapter
            --enable casting to an integer from view
            view.metamethods.__cast = function(from, to, exp)
                if from:isstruct() and to:isintegral() then
                    return quote
                        var x = exp
                    in
                        [int64](x.size)
                    end
                end
            end
            --create and return wrapper object by value
            return quote
                var v = view{n}
            in
                v
            end
        end)
    return factory
end

local adapter_simple_factory = function(Adapter)
    local factory = macro(function()
        --wrapper struct
        local struct simple{
        }
        simple.generator = Adapter
        --create and return simple object by value
        return quote
            var v = simple{}
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

local newcombiner = function(Ranges, name)
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
    combirange.metamethods.__for = function(self,body)
        local D = #Ranges
        if D==1 then
            return quote
                var iter = self
                for u in iter._0 do
                    [body(u)]
                end
            end
        elseif D==2 then
            return quote
                var iter = self
                var state_0, value_0 = iter._0:getfirst()
                var state_1, value_1 = iter._1:getfirst()
                while not (iter._0:islast(state_0, value_0) or iter._1:islast(state_1, value_1)) do
                    [body(value_0, value_1)]
                    value_0 = iter._0:getnext(state_0)
                    value_1 = iter._1:getnext(state_1)
                end
            end
        elseif D==3 then
            return quote
                var iter = self
                var state_0, value_0 = iter._0:getfirst()
                var state_1, value_1 = iter._1:getfirst()
                var state_2, value_2 = iter._2:getfirst()
                while not (iter._0:islast(state_0, value_0) or iter._1:islast(state_1, value_1) or iter._2:islast(state_2, value_2)) do
                    [body(value_0, value_1, value_2)]
                    value_0 = iter._0:getnext(state_0)
                    value_1 = iter._1:getnext(state_1)
                    value_2 = iter._2:getnext(state_2)
                end
            end
        end
    end

    return combirange
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

--export functionality for developing new ranges
local develop = {
    RangeBase = RangeBase,
    factory = { 
        combiner = combiner_factory,
        simple_adapter = adapter_simple_factory,
        view_adapter = adapter_view_factory,
        lambda_adapter = adapter_view_factory
    },
    newcombinerstruct = newcombiner,
}


local Ranger = function(T) 
return interface.Interface:new{
    first = {} -> {T},
	next = {T} -> {T}
}
end

--return module
return {
    Base = RangeBase,
    Linrange = Linrange,
    transform = transform,    
    filter = filter,
    take = take,
    drop = drop, 
    take_while = take_while,
    drop_while = drop_while,
    enumerate = enumerate,
    join = join,
    product = product,
    zip = zip,
    develop
}