-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local interface = require("interface")
local lambdas = require("lambdas")
local err = require("assert")
local io = terralib.includec("stdio.h")

local size_t = uint64

--the following interface is used to collect elements in
--a range
local Stacker = terralib.memoize(
    function(T)
        return interface.Interface:new{
            size = {} -> uint64,
            push = {T} -> {},
            pop = {} -> {T}
        }
    end
)

--an iterator implements the following macros:
--  methods.getfirst :: (self) -> (state, value)
--  methods.getnext :: (self, state) -> (value)
--  methods.islast :: (self, state, value) -> (true/false)
--the following base class then overloads the '>>' operator
--and adds the '__for' metamethod, and adds a 'collect' 
--method that collects all elements in the range in a container
--that satsifies the 'Stacker(T)' interface
--ToDo - maybe its possible to use (mutating) terra functions 
--rather than macros.
local RangeBase = function(Range, T)

    --set the element type of the range
    Range.eltype = T

    --overloading '>>' operator
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

    --__for is generated for iterators
    Range.metamethods.__for = function(self,body)
        return quote
            var iter = self
            var state, value = iter:getfirst()
            if not iter:islast(state, value) then
                repeat
                    [body(value)]
                    value = iter:getnext(state)
                until iter:islast(state, value)
            end
        end
    end

    --collect requires only the 'Stacker' interface
    local S = Stacker(T)
    terra Range:collect(container : S)
        for v in self do
            container:push(v)
        end
    end

end

--convenience macro that yields the next value that satisfies the predicate
local __getnextvalue_that_satisfies_predicate = macro(function(self, state, value, condition)
    local condition = condition or false
    return quote
        while self.predicate(value)==condition do
            if self.range:islast(state, value) then break end
            value = self.range:getnext(state)
        end
    end
end)

local Unitrange = function(T)

    local struct range{
        a : T
        b : T
    }

    range.staticmethods = {}

    range.metamethods.__getmethod = function(self, methodname)
        return self.methods[methodname] or range.staticmethods[methodname]
    end

    local new = terra(a : T, b : T, include_last : bool)
        err.assert((b-a) > 0)
        var size = [size_t](b-a) + [int](include_last)
        return range{a, a + size}
    end

    range.staticmethods.new = terralib.overloadedfunction("new",{
        new,
        terra(a : T, b : T) return new(a, b, false) end
    })

    terra range:size()
        return self.b - self.a
    end

    range.methods.getfirst = macro(function(self)
        return quote 
        in
            0, self.a
        end
    end)

    range.methods.getnext = macro(function(self, state)
        return quote 
            state = state + 1
            var value = self.a + state
        in
            value
        end
    end)

    range.methods.islast = macro(function(self, state, value)
        return quote 
            var terminate = (state == self:size())
        in
            terminate
        end
    end)

    --add metamethods
    RangeBase(range, T)

    range.metamethods.__apply = terra(self : &range, i : size_t)
        err.assert(i < self:size())
        return self.a + i
    end

    return range
end

local Steprange = function(T)

    local struct range{
        a : T
        b : T
        step : T
    }

    range.staticmethods = {}

    range.metamethods.__getmethod = function(self, methodname)
        return self.methods[methodname] or range.staticmethods[methodname]
    end

    local new = terra(a : T, b : T, step : T, include_last : bool)
        err.assert(((b-a) >= 0 and step > 0) or ((b-a) <= 0 and step < 0))
        b = terralib.select(b > a, b + [int](include_last), b - [int](include_last))
        b = b + (b - a) % step
        return range{a, b, step}
    end

    range.staticmethods.new = terralib.overloadedfunction("new",{
        new,
        terra(a : T, b : T, step : T) return new(a, b, step, false) end
    })
    
    terra range:size() : size_t
        return (self.b-self.a) / self.step
    end

    range.methods.getfirst = macro(function(self)
        return quote 
        in
            self.a, self.a
        end
    end)

    range.methods.getnext = macro(function(self, state)
        return quote 
            state = state + self.step
            var value = state
        in
            value
        end
    end)

    range.methods.islast = macro(function(self, state, value)
        return quote 
            var terminate = (value == self.b)
        in
            terminate
        end
    end)

    --add metamethods
    RangeBase(range, T)

    range.metamethods.__apply = terra(self : &range, i : size_t)
        err.assert(i < self:size())
        return self.a + i * self.step
    end

    return range
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

    local struct adapter{
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

--factory function for range adapters that carry a lambda
local adapter_lambda_factory = function(Adapter)
    local factory = macro(
        function(fun, ...)
            --get the captured variables
            local captures = {...}
            local p = lambdas.lambda_generator(fun, ...)
            --set the generator (FilteredRange or TransformedRange, etc)
            p.generator = Adapter
            --create and return lambda object by value
            return quote
                var f = p{[captures]}
            in
                f
            end
        end)
    return factory
end

--factory function for range adapters that carry a view
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

--factory function for range adapters that don't cary state
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

--factory function for range combiners
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

local Enumerator = function(Ranges)

    --check that a range-for is implemented
    assert(#Ranges==1)
    local Range = Ranges[1]
    assert(Range.metamethods.__for)

    local struct enumerator{
        range : Range
    }

    enumerator.metamethods.__for = function(self,body)
        return quote
            var iter = self
            var i = 0
            for v in iter.range do
                [body(i,v)]
                i = i + 1
            end
        end
    end

    return enumerator
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
        if D > 3 then
            error("Product range is only implemented for D=1,2,3.") 
            -- right now only implemented for D=1,2,3
            --ToDo: eventially implement using 'getfirst', 'getnext', 'islast'?
        end
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
        if D > 3 then
            error("Zip range is only implemented for D=1,2,3.") 
            -- right now only implemented for D=1,2,3
            --ToDo: eventially implement using 'getfirst', 'getnext', 'islast'?
        end
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
--generate user api macro's for combi-ranges
local enumerate = combiner_factory(Enumerator)
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

--return module
return {
    include_last = true,
    Base = RangeBase,
    Unitrange = Unitrange,
    Steprange = Steprange,
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
    develop = develop
}