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
local RangeBase = function(Range, state_t, T)

    --set the value type and state type of the range
    Range.state_t = state_t
    Range.value_t = T

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
            if not iter:islast(&state, &value) then
                repeat
                    [body(value)]
                    value = iter:getnext(&state)
                until iter:islast(&state, &value)
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
local __getnextvalue_that_satisfies_predicate = macro(function(range, state, value, predicate, condition)
    local condition = condition or false
    local predicate_t = predicate.tree.type
    if predicate_t.byreference then
        return quote
            while predicate(value)==condition do
                if range:islast(state, value) then break end
                @value = range:getnext(state)
            end
        end
    else
        return quote
            while predicate(@value)==condition do
                if range:islast(state, value) then break end
                @value = range:getnext(state)
            end
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

    terra range:getfirst()
        return self.a, self.a
    end

    terra range:getnext(state : &T)
        @state = @state + 1
        return @state
    end

    terra range:islast(state : &T, value : &T)
        return @state == self.b
    end

    --add metamethods
    RangeBase(range, T, T)

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

    terra range:getfirst()
        return self.a, self.a
    end

    terra range:getnext(state : &T)
        @state = @state + self.step
        return @state
    end

    terra range:islast(state : &T, value : &T)
        return @state == self.b
    end

    --add metamethods
    RangeBase(range, T, T)

    range.metamethods.__apply = terra(self : &range, i : size_t)
        err.assert(i < self:size())
        return self.a + i * self.step
    end

    return range
end

local FilteredRange = function(Range, Function)

    --check that function is a predicate
    assert(Function.returntype == bool)
    Function.byreference = Function.parameters[1]:ispointer()

    local struct adapter{
        range : Range
        predicate : Function
    }

    local S = Range.state_t
    local T = Range.value_t

    terra adapter:getfirst()
        var state, value = self.range:getfirst()
        __getnextvalue_that_satisfies_predicate(self.range, &state, &value, self.predicate)
        return state, value
    end

    terra adapter:getnext(state : &S)
        var value = self.range:getnext(state)
        __getnextvalue_that_satisfies_predicate(self.range, state, &value, self.predicate)
        return value
    end

    terra adapter:islast(state : &S, value : &T)
        return self.range:islast(state, value)
    end

    --add metamethods
    RangeBase(adapter, S, T)

    return adapter
end

local TransformedRange = function(Range, Function)

    local struct adapter{
        range : Range
        f : Function
    }

    local S = Range.state_t
    local T = Function.returntype
    Function.byreference = Function.parameters[1]:ispointer()

    terra adapter:getfirst()
        var state, value = self.range:getfirst()
        escape
            if Function.byreference then
                emit quote return state, self.f(&value) end
            else
                emit quote return state, self.f(value) end
            end
        end
    end

    terra adapter:getnext(state : &S)
        var value = self.range:getnext(state)
        escape
            if Function.byreference then
                emit quote return self.f(&value) end
            else
                emit quote return self.f(value) end
            end
        end
    end

    terra adapter:islast(state : &S, value : &T)
        return self.range:islast(state, value)
    end

    --add metamethods
    RangeBase(adapter, S, T)

    return adapter
end

local TakeRange = function(Range)

    local struct adapter{
        range : Range
        take : int64
    }
    local S = Range.state_t
    local T = Range.value_t

    terra adapter:getfirst()
        return self.range:getfirst()
    end

    terra adapter:getnext(state : &S)
        self.take = self.take - 1
        return self.range:getnext(state)
    end

    terra adapter:islast(state : &S, value : &T)
        return (self.take == 0) or self.range:islast(state, value)
    end

    --add metamethods
    RangeBase(adapter, S, T)

    return adapter
end

local DropRange = function(Range)

    local struct adapter{
        range : Range
        drop : int64
    }
    local S = Range.state_t
    local T = Range.value_t

    terra adapter:getfirst()
        var state, value = self.range:getfirst()
        var drop = self.drop
        for k = 0, drop do
            value = self.range:getnext(&state)
            self.drop = self.drop - 1
        end
        return state, value
    end

    terra adapter:getnext(state : &S)
        return self.range:getnext(state)
    end

    terra adapter:islast(state : &S, value : &T)
        return self.range:islast(state, value)
    end

    --add metamethods
    RangeBase(adapter, S, T)

    return adapter
end


local TakeWhileRange = function(Range, Function)

    --check that function is a predicate
    assert(Function.returntype == bool)

    local struct adapter{
        range : Range
        predicate : Function
    }
    local S = Range.state_t
    local T = Range.value_t

    terra adapter:getfirst()
        return self.range:getfirst()
    end

    terra adapter:getnext(state : &S)
        return self.range:getnext(state)
    end

    terra adapter:islast(state : &S, value : &T)
        return self.predicate(@value)==false
    end

    --add metamethods
    RangeBase(adapter, S, T)

    return adapter
end

local DropWhileRange = function(Range, Function)

    local struct adapter{
        range : Range
        predicate : Function
    }
    local S = Range.state_t
    local T = Range.value_t
    Function.byreference = Function.parameters[1]:ispointer()

    terra adapter:getfirst()
        var state, value = self.range:getfirst()
        __getnextvalue_that_satisfies_predicate(self.range, &state, &value, self.predicate, true)
        return state, value
    end

    terra adapter:getnext(state : &S)
        return self.range:getnext(state)
    end

    terra adapter:islast(state : &S, value : &T)
        return self.range:islast(state, value)
    end

    --add metamethods
    RangeBase(adapter, S, T)

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
		combiner.entries:insert({field = "_"..tostring(i-1), type = Range})
	end
    combiner:setconvertible("tuple")
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
    local D = #Ranges

    --get range types
    local T = Ranges[1].value_t
    local S = Ranges[1].state_t
    for i,rn in ipairs(Ranges) do
        assert(rn.value_t == T and rn.state_t==S)
    end

    local struct istate{
        state : S
        index : uint8
    }

    terra combirange:getfirst()
        var state, value = self._0:getfirst()
        return istate{state, 0}, value
    end

    terra combirange:getnext(state : &istate)
        escape
            for k=0,D-1 do
                local s = "_"..tostring(k)
                emit quote
                    if state.index==[k] then
                        return self.[s]:getnext(&state.state)
                    end
                end
            end
        end
    end

    terra combirange:islast(state : &istate, value : &T)
        escape
            for k=0,D-2 do
                local s1 = "_"..tostring(k)
                local s2 = "_"..tostring(k+1)
                emit quote
                    if state.index==[k] then
                        if self.[s1]:islast(&state.state, value) then
                            state.index = state.index+1
                            state.state, @value = self.[s2]:getfirst()
                            
                        end
                        return false
                    end
                end
            end
            local s = "_"..tostring(D-1)
            emit quote
                if state.index==[D-1] then
                    return self.[s]:islast(&state.state, value)
                end
            end
        end
    end

    --add metamethods
    RangeBase(combirange, istate, T)

    return combirange
end

local ProductRange = function(Ranges)
  
    local combirange = newcombiner(Ranges, "product")
    local D = #Ranges

    local value_t = terralib.newlist{}
    local state_t = terralib.newlist{}
    for i,rn in ipairs(Ranges) do
        value_t:insert(rn.value_t)
        state_t:insert(rn.state_t)
    end
    local S = tuple(unpack(state_t))
    local T = tuple(unpack(value_t))

    local struct istate{
        state : S
        value : &T
    }
    istate:complete()

    local getfirst = function(self, state, value, k) 
        local s = "_"..tostring(k)
        return quote
            state.[s], value.[s] = self.[s]:getfirst()
        end
    end

    local getnext = function(self, state, value, k) 
        local s = "_"..tostring(k)
        return quote
            value.[s] = self.[s]:getnext(&state.[s])
        end
    end

    local islast = function(self, state, value, k)
        local s = "_"..tostring(k)
        return `self.[s]:islast(&state.[s], &value.[s])
    end

    terra combirange:getfirst()
        var state : istate
        var value : T
        state.value = &value
        escape
            for k=0, D-1 do
                emit quote [getfirst(`self, `state.state, `value, k)] end
            end
        end
        return state, value
    end

    terra combirange:getnext(state : &istate)
        [getnext(`self, `state.state, `@state.value, 0)]
        return @state.value
    end

    terra combirange:islast(state : &istate, value : &T)
        state.value = value
        escape
            --loop over each of the D ranges
            for k=0, D-2 do
                emit quote
                    if [islast(`self, `state.state, `@value, k)] then
                        [getfirst(`self, `state.state, `@value, k)]
                        [getnext(`self, `state.state, `@value, k+1)]     --increment range k+1
                    else
                        return false
                    end
                end
            end
        end
        return [islast(`self, `state.state, `@value, D-1)]
    end

    --add metamethods
    RangeBase(combirange, istate, T)

    return combirange
end

local ZipRange = function(Ranges)
  
    local combirange = newcombiner(Ranges, "zip")
    local D = #Ranges

    --get range types
    local value_t = terralib.newlist{}
    local state_t = terralib.newlist{}
    for i,rn in ipairs(Ranges) do
        value_t:insert(rn.value_t)
        state_t:insert(rn.state_t)
    end
    local S = tuple(unpack(state_t))
    local T = tuple(unpack(value_t))

    local getfirst = function(self, state, value, k) 
        local s = "_"..tostring(k)
        return quote
            state.[s], value.[s] = self.[s]:getfirst()
        end
    end

    local getnext = function(self, state, value, k) 
        local s = "_"..tostring(k)
        return quote
            value.[s] = self.[s]:getnext(&state.[s])
        end
    end

    local islast = function(self, state, value, k)
        local s = "_"..tostring(k)
        return `self.[s]:islast(&state.[s], &value.[s])
    end

    terra combirange:getfirst()
        var state : S
        var value : T
        escape
            for k=0, D-1 do
                emit quote [getfirst(`self, `state, `value, k)] end
            end
        end
        return state, value
    end

    terra combirange:getnext(state : &S)
        var value : T
        escape
            for k=0, D-1 do
                emit quote [getnext(`self, `@state, `value, k)] end
            end
        end
        return value
    end

    terra combirange:islast(state : &S, value : &T)
        escape
            --loop over each of the D ranges
            for k=0, D-1 do
                emit quote
                    if [islast(`self, `@state, `@value, k)] then
                        return true
                    end
                end
            end
        end
        return false
    end
    
    --add metamethods
    RangeBase(combirange, S, T)

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