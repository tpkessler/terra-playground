local concepts = require "concepts"

local concept = concepts.concept

local function template()
    local mt = {}
    local fn = {}
    local any = concept("Any")
    any.default = function (...) return true end

    --returning an error if a valid implementation is missing
    local function error_implementation_missing(...)
        error("Implementation missing.", 2)
    end
    --returning an error if a method call is ambiguous
    local function error_ambiguous_call(...)
        error("Method call is ambiguous.", 2)
    end
    --check if method signature satisfies method concepts
    --this is used to rule out methods, such that only admissable
    --methods remain
    local function concepts_check(concepts, args)
        --at least the minimal number of arguments must match
        if not (#concepts==#args) then
            return false
        end
        --check of concept is satisfied for each corresponding
        --argument
        for i,concept in ipairs(concepts) do
            --if one of the concepts is not satisfied then return false
            if not concept(args[i]) then
                return false
            end
        end
        --if all concepts are satisfied return true
        return true
    end
    --return a table of admissable methods.
    --this method is only called if the number of arguments is more than one.
    local function get_methods(...)
        local args = {...} --tabulate input arguments
        local methods = {} --table for storing admissable methods
        for concepts, _ in pairs(fn) do
            --expecting a table of concepts, not a single one
            if concepts.type~="concept" and type(concepts)=="table" then
                --if the arguments satisfy the concepts then
                --add method to methods table
                if concepts_check(concepts, args) then
                    table.insert(methods, concepts)
                end
            end
        end
        return methods
    end
    --compare two method signatures based on their concepts and check which
    --one is more specialized
    local function compare_two_methods(c_1, c_2)
        local n, n_2 = #c_1, #c_2
        assert(n==n_2, "Expected arrays to have the same length.")
        --compare each equivalence class, and keep score
        local s_1, s_2 = 0, 0
        for i=1,n do
            if c_1[i]:subtypeof(c_2[i]) then
                s_1 = s_1 + 1
            elseif c_1[i]:supertypeof(c_2[i]) then
                s_2 = s_2 + 1
            end
        end
        --comparison of equivalence classes
        if s_1==s_2 then
            --return 0 if signatures are ambiguous
            return 0
        else
            --return -1 if c_2 is more specialized
            if s_1 < s_2 then
                return -1
            --return +1 if c_1 is more specialized
            else
                return 1
            end
        end
    end
    --select a method in case of a single input argument
    local function select_method_single_argument(T)
        local saved = any
        --get minimal element
        for concept,_ in pairs(fn) do
            if concept.type=="concept" and concept(T) then
                if concept:subtypeof(saved) then saved = concept end
            end
        end
        --ToDo: check for an ambiguous call? Can that happen
        --in case of a single argument call?
        return fn[saved]
    end
    --return table of admissable methods. It contains only one
    --element if the cass is not ambiguous
    local function select_method_multiple_arguments(...)
        --get admissable methods
        local t = {...}
        local admissable = get_methods(...)
        --find a minimal element
        local saved = {}
        for i=1,#t do
            table.insert(saved,any)
        end
        for _,concepts in ipairs(admissable) do
            local s = compare_two_methods(concepts, saved)
            if s==1 then
                saved = concepts
            end
        end
        --check if there are other minimal elements, that is,
        --is the call ambiguous?
        local methods = {}
        for _,concepts in ipairs(admissable) do
            local s = compare_two_methods(concepts, saved)
            if s==0 then
                table.insert(methods, concepts)
            end
        end
        return methods
    end
    --overloading the call operator
    function mt:__call(...)
        local args = {...}
        if #args==1 then
            local f = select_method_single_argument(args[1])
            return (f or self.default)(args[1])
        else
            local methods = select_method_multiple_arguments(...)
            if #methods>1 then
                print("Warning: The following method calls are ambiguous: ")
                for i,m in ipairs(methods) do
                    local f = fn[m] 
                    print(tostring(f))
                end
                --throw error that call is ambiguous
                return error_ambiguous_call(...)
            end
            return (fn[methods[1]] or self.default)(...)
        end
    end
    --custom set method for adding methods
    function mt:__newindex(key, value)
        fn[key] = value
    end

    return setmetatable({default = error_implementation_missing}, mt)
end

--lua function to create a concept. A concept defines a concept
--defines a compile-time predicate that defines an equivalence 
--relation on a set.
local concept = concepts.concept

--primitive number concepts
local Float32 = concept(float)
local Float64 = concept(double)
local Int8    = concept(int8)
local Int16   = concept(int16)
local Int32   = concept(int32)
local Int64   = concept(int64)

-- abstract floating point numbers
local Float = concept("Float")
Float.float = Float32
Float.double = Float64

--abstract integers
local Integer = concept("Integer")
-- the definition below where we use concepts as 
-- functors not longer works when we implement 
-- concepts as types
Integer.int = Int32
Integer.int8 = Int8
Integer.int16 = Int16
Integer.int32 = Int32
Integer.int64 = Int64

--test foo template implementation
local foo = template()

foo[Integer] = function(T)
    print("Method for {Integer}")
end

foo[Float] = function(T)
    print("Method for {Float}")
end

foo[{Integer,Integer}] = function(T1, T2)
    print("Method for {Integer,Integer}")
end

foo[{Integer,Int32}] = function(T1, T2)
    print("Method for {Integer,Int32}")
end

foo[{Int32,Integer}] = function(T1, T2)
    print("Method for {Int32,Integer}")
end

foo[{Int32,Integer,Float}] = function(T1, T2, T3)
    print("Method for {Int32,Integer,Float}")
end

foo[{Int32,Int32,Float}] = function(T1, T2, T3)
    print("Method for {Int32,Int32,Float}")
end

foo[{Int32,Int32,Float64}] = function(T1, T2, T3)
    print("Method for {Int32,Int32,Float64}")
end

foo(double)
foo(int32)
foo(int64, int64)
foo(int32, int32, double)


--uncomment to see the following fail due to the presence of
--two ambiguous methods
--foo(int32, int32)

--removing the ambiguity by defining the specialization
foo[{Int32,Int32}] = function(T1, T2)
    print("Method for {Int32,Int32}")
end

--try again
foo(int32, int32)
