-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local base = require("base")
local concept = require("concept")
local template = require("template")
local lambdas = require("lambdas")
local err = require("assert")

local size_t = uint64

--collect requires a stacker interface or a setter interface
--stacker interface
local Stacker = concept.AbstractInterface:new("Stacker")
Stacker:addmethod{push = {concept.Any} -> {}}
--setter interface
local Setter = concept.AbstractInterface:new("Setter")
Setter:addmethod{set = {concept.Integral, concept.Any} -> {}}
--arraylike implements both the setter and the stacker interface
local Sequence = concept.AbstractInterface:new("Sequence")
Sequence:inheritfrom(Stacker)
Sequence:inheritfrom(Setter)

--an iterator implements the following macros:
--  methods.getfirst :: (self) -> (state, value)
--  methods.getnext :: (self, state) -> (value)
--  methods.isvalid :: (self, state, value) -> (true/false)
--the following base class then overloads the '>>' operator
--and adds the '__for' metamethod, and adds a 'collect' 
--method that collects all elements in the range in a container
--that satsifies the 'Stacker(T)' interface
--ToDo - maybe its possible to use (mutating) terra functions 
--rather than macros.
local RangeBase = function(Range, Iter_t, T)

    --set the value type and iterator type of the range
    Range.state_t = Iter_t
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

    --always extract a value type into the body of the loop
    local extract = function(value) 
        if value.type:ispointer() then
            return `@value
        else
            return `value
        end
    end

    --__for is generated for iterators
    Range.metamethods.__for = function(self,body)
        return quote
            var range = self
            var iter = range:getfirst()
            while range:isvalid(&iter) do
                var value = range:getvalue(&iter)
                [body(extract(value))] --run body of loop
                range:next(&iter) --increment state
            end
        end
    end

    --definition of collect template
    Range.templates.collect = template.Template:new("collect")
    --containers implementing the stacker interface only
    Range.templates.collect[{&Range.Self, &Stacker} -> {}] = function(Self, Container)
        return terra(self : Self, container : Container)
            for v in self do
                container:push(v)
            end
        end
    end
    --containers that only implement the setter interface arte using 'set'. Sufficient
    --space needs to be allocated before
    Range.templates.collect[{&Range.Self, &Setter} -> {}] = function(Self, Container)
        return terra(self : Self, container : Container)
            var i = 0
            for v in self do
                container:set(i, v)
                i = i + 1
            end
        end
    end
    --containers implementing the stacker and setter interface will only use
    --the stacker interface
    Range.templates.collect[{&Range.Self, &Sequence} -> {}] = function(Self, Container)
        return terra(self : Self, container : Container)
            for v in self do
                container:push(v)
            end
        end
    end

end

local Unitrange = function(T)

    local struct range{
        a : T
        b : T
    }
    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concept-based function overloading at compile-time
    base.AbstractBase(range)

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
        return self.a
    end

    terra range:getvalue(iter : &T)
        return @iter
    end

    terra range:next(iter : &T)
        @iter = @iter + 1
    end

    terra range:isvalid(iter : &T)
        return @iter < self.b
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
    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concept-based function overloading at compile-time
    base.AbstractBase(range)

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
        return self.a
    end

    terra range:getvalue(iter : &T)
        return @iter
    end

    terra range:next(iter : &T)
        @iter = @iter + self.step
    end

    terra range:isvalid(iter : &T)
        return terralib.select(self.step>0, @iter < self.b, @iter > self.b)
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

    local struct adapter{
        range : Range
        predicate : Function
    }
    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concept-based function overloading at compile-time
    base.AbstractBase(adapter)

    --select by value or by reference
    Function.byreference = Function.parameters[1]:ispointer()
    --evaluate predicate
    local pred = macro(function(self, value)
        if Function.byreference then
            return `self.predicate(&value)
        else
            return `self.predicate(value)
        end
    end)

    local S = Range.state_t --iterator type (a pointer or a struct holding a pointer)
    local T = Range.value_t

    terra adapter:getfirst()
        var state = self.range:getfirst()
        var v = self.range:getvalue(&state)
        if pred(self,v)==false then
            self:next(&state)
        end
        return state
    end

    terra adapter:getvalue(state : &S)
        return self.range:getvalue(state)
    end

    terra adapter:next(state : &S)
        self.range:next(state)
        while (self.range:isvalid(state) and pred(self,self.range:getvalue(state))==false) do
            self.range:next(state)
        end
    end

    terra adapter:isvalid(state : &S)
        return self.range:isvalid(state)
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
    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concept-based function overloading at compile-time
    base.AbstractBase(adapter)

    local S = Range.state_t
    local T = Function.returntype

    --select by value or by reference
    Function.byreference = Function.parameters[1]:ispointer()
    --valuate transform
    local transform = macro(function(self, value)
        if Function.byreference then
            return `self.f(&value)
        else
            return `self.f(value)
        end
    end)

    local struct iter{
        state : S
    }

    terra adapter:getfirst()
        return iter{self.range:getfirst()}
    end

    terra adapter:getvalue(state : &iter)
        return transform(self, self.range:getvalue(&state.state))
    end

    terra adapter:next(state : &iter)
        self.range:next(&state.state)
    end

    terra adapter:isvalid(state : &iter)
        return self.range:isvalid(&state.state)
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
    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concept-based function overloading at compile-time
    base.AbstractBase(adapter)

    local S = Range.state_t
    local T = Range.value_t

    terra adapter:getfirst()
        return self.range:getfirst()
    end

    terra adapter:getvalue(state : &S)
        return self.range:getvalue(state)
    end

    terra adapter:next(state : &S)
        self.take = self.take - 1
        self.range:next(state)
    end

    terra adapter:isvalid(state : &S)
        return (self.take > 0) and self.range:isvalid(state)
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
    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concept-based function overloading at compile-time
    base.AbstractBase(adapter)

    local S = Range.state_t
    local T = Range.value_t

    terra adapter:getfirst()
        var state = self.range:getfirst()
        for k = 0, self.drop do
            self.range:next(&state)
            if not self.range:isvalid(&state) then
                break
            end
        end
        return state
    end

    terra adapter:getvalue(state : &S)
        return self.range:getvalue(state)
    end

    terra adapter:next(state : &S)
        self.range:next(state)
    end

    terra adapter:isvalid(state : &S)
        return self.range:isvalid(state)
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
    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concept-based function overloading at compile-time
    base.AbstractBase(adapter)

    --select by value or by reference
    Function.byreference = Function.parameters[1]:ispointer()
    --evaluate predicate
    local pred = macro(function(self, value)
        if Function.byreference then
            return `self.predicate(&value)
        else
            return `self.predicate(value)
        end
    end)

    local S = Range.state_t --iterator type (a pointer or a struct holding a pointer)
    local T = Range.value_t

    terra adapter:getfirst()
        return self.range:getfirst()
    end

    terra adapter:getvalue(state : &S)
        return self.range:getvalue(state)
    end

    terra adapter:next(state : &S)
        self.range:next(state)
    end

    terra adapter:isvalid(state : &S)
        return self.range:isvalid(state) and pred(self,self.range:getvalue(state))==true
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
    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concept-based function overloading at compile-time
    base.AbstractBase(adapter)

    --select by value or by reference
    Function.byreference = Function.parameters[1]:ispointer()
    --evaluate predicate
    local pred = macro(function(self, value)
        if Function.byreference then
            return `self.predicate(&value)
        else
            return `self.predicate(value)
        end
    end)

    local S = Range.state_t
    local T = Range.value_t

    terra adapter:getfirst()
        var state = self.range:getfirst()
        while (self.range:isvalid(&state) and pred(self,self.range:getvalue(&state))==true) do
            self.range:next(&state)
        end
        return state
    end

    terra adapter:getvalue(state : &S)
        return self.range:getvalue(state)
    end

    terra adapter:next(state : &S)
        return self.range:next(state)
    end

    terra adapter:isvalid(state : &S)
        return self.range:isvalid(state)
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
    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concept-based function overloading at compile-time
    base.AbstractBase(combirange)
    local D = #Ranges

    --get range types
    local T = Ranges[1].value_t
    local S = Ranges[1].state_t
    for i,rn in ipairs(Ranges) do
        assert(rn.value_t == T and rn.state_t==S)
    end

    local struct iterator{
        state : S
        index : uint8
    }
    

    terra combirange:getfirst()
        return iterator{self._0:getfirst(), 0}
    end

    terra combirange:getvalue(iter : &iterator)
        escape
            for k=0,D-1 do
                local s = "_"..tostring(k)
                emit quote
                    if iter.index==[k] then
                        return self.[s]:getvalue(&iter.state)
                    end
                end
            end
        end
    end

    terra combirange:next(iter : &iterator)
        escape
            for k=0,D-1 do
                local s = "_"..tostring(k)
                emit quote
                    if iter.index==[k] then
                        return self.[s]:next(&iter.state)
                    end
                end
            end
        end
    end

    terra combirange:isvalid(iter : &iterator)
        escape
            for k=0,D-2 do
                local s1 = "_"..tostring(k)
                local s2 = "_"..tostring(k+1)
                emit quote
                    if iter.index==[k] then
                        if not self.[s1]:isvalid(&iter.state) then
                            iter.index = iter.index+1
                            iter.state = self.[s2]:getfirst()
                        end
                        return true
                    end
                end
            end
            local s = "_"..tostring(D-1)
            emit quote
                if iter.index==[D-1] then
                    return self.[s]:isvalid(&iter.state)
                end
            end
        end
    end

    --add metamethods
    RangeBase(combirange, iterator, T)

    return combirange
end


local ZipRange = function(Ranges)
  
    local combirange = newcombiner(Ranges, "zip")
    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concept-based function overloading at compile-time
    base.AbstractBase(combirange)
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

    local getfirst = function(self, iter, k) 
        local s = "_"..tostring(k)
        return quote
            iter.[s] = self.[s]:getfirst()
        end
    end

    local getvalue = function(self, iter, value, k)
        local s = "_"..tostring(k)
        return quote
            value.[s] = self.[s]:getvalue(&iter.[s])
        end
    end

    local next = function(self, iter, k) 
        local s = "_"..tostring(k)
        return quote
            self.[s]:next(&iter.[s])
        end
    end

    local isvalid = function(self, iter, k)
        local s = "_"..tostring(k)
        return `self.[s]:isvalid(&iter.[s])
    end

    terra combirange:getfirst()
        var iter : S
        escape
            for k=0, D-1 do
                emit quote [getfirst(`self, `iter, k)] end
            end
        end
        return iter
    end

    terra combirange:getvalue(iter : &S)
        var value : T
        escape
            for k=0, D-1 do
                emit quote [getvalue(`self, `@iter, `value, k)] end
            end
        end
        return value
    end

    terra combirange:next(iter : &S)
        escape
            for k=0, D-1 do
                emit quote [next(`self, `@iter, k)] end
            end
        end
    end

    terra combirange:isvalid(iter : &S)
        escape
            --loop over each of the D ranges
            for k=0, D-1 do
                emit quote
                    if not [isvalid(`self, `@iter, k)] then
                        return false
                    end
                end
            end
            emit quote return true end
        end
        return false
    end
    
    --add metamethods
    RangeBase(combirange, S, T)

    return combirange
end

local ProductRange = function(Ranges)
  
    local combirange = newcombiner(Ranges, "product")
    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concept-based function overloading at compile-time
    base.AbstractBase(combirange)
    local D = #Ranges

    local value_t = terralib.newlist{}
    local state_t = terralib.newlist{}
    for i,rn in ipairs(Ranges) do
        value_t:insert(rn.value_t)
        state_t:insert(rn.state_t)
    end
    local S = tuple(unpack(state_t))
    local T = tuple(unpack(value_t))

    local struct iterator{
        state : S
        value : T
    }
    iterator:complete()

    local getfirst = function(self, iter, k) 
        local s = "_"..tostring(k)
        return quote
            iter.[s] = self.[s]:getfirst()
        end
    end

    local getvalue = function(self, iter, value, k) 
        local s = "_"..tostring(k)
        return quote
            value.[s] = self.[s]:getvalue(&iter.[s])
        end
    end

    local next = function(self, iter, k)
        local s = "_"..tostring(k)
        return quote
            self.[s]:next(&iter.[s])
        end
    end

    local isvalid = function(self, iter, k)
        local s = "_"..tostring(k)
        return `self.[s]:isvalid(&iter.[s])
    end

    terra combirange:getfirst()
        var iter : iterator
        escape
            for k=0, D-1 do
                emit quote [getfirst(`self, `iter.state, k)] end
                emit quote [getvalue(`self, `iter.state, `iter.value, k)] end
            end
        end
        return iter
    end

    terra combirange:getvalue(iter : &iterator)
        return iter.value
    end

    terra combirange:next(iter : &iterator)
        escape
            for k=0, D-2 do
                emit quote
                    --increase k
                    [next(`self, `iter.state, k)]
                    if [isvalid(`self, `iter.state, k)] then
                        [getvalue(`self, `iter.state, `iter.value, k)]
                        return
                    end
                    --reset k
                    [getfirst(`self, `iter.state, k)]
                    [getvalue(`self, `iter.state, `iter.value, k)]
                end
            end
        end
        --increase D-1
        [next(`self, `iter.state, D-1)]
        if [isvalid(`self, `iter.state, D-1)] then
            [getvalue(`self, `iter.state, `iter.value, D-1)]
        end
    end

    terra combirange:isvalid(iter : &iterator)
        return [isvalid(`self, `iter.state, D-1)]
    end

    --add metamethods
    RangeBase(combirange, iterator, T)

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
