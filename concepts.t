local concepts = {}
--[[
A 'concept' defines an equivalence class, that is, a set with an equivalence relation by which objects in the set may be compared. Each concept is a table that behaves like a lua function object: a boolean predicate. A function call yields a boolean value that signals that the input belongs to the equivalence class or not.
```docexample
    --create a concept 'c = concept(<name>)' where <name> is a string, e.g.
    local Integer = concept("Integer")

    --Define the equivalence relation
    --The following default is automatic and need not be explicitly set
    Integer.default= function(T) return T.name=="Integer" end
    Integer.int32 = function return true end
    Integer.int64 = function return true end
    --the notation Integer.<name> is used to perform method selection. Terra --primitive types have a .name property. For example int32.name=="int32".
    
    --now you can call:
    assert(Integer(Integer))
    assert(Integer(int32))
    assert(Integer(int64))
    assert(Integer(double)==false)

    --create concepts for concrete terra types. Proper defaults are automatically --handled as long as the terra objects have a <.name> method.
    local Int32 = concept(int32)
    local Int64 = concept(int64)
    local Float32 = concept(float)
    
    --the equivalence relation makes it now possible to compare concepts
    assert(Int32:subtypeof(Integer))
    assert(Int64:subtypeof(Integer))
    assert(Integer == Integer)
    assert(Int32:supertypeof(Integer) == false)
    assert(Float64:subtypeof(Integer) == false)
``` 
```docexample
    --Concepts can represent abstract types. But concepts can also define other --equivalence relations, e.g. to check if one number is convertible to another
    local is_convertible_to = concept("is_convertible_to")

    --Define the equivalence relation
    is_convertible_to.default = function(T1,T2) return false end
    is_convertible_to.int32_int64 = function(T1,T2) return true end
    is_convertible_to.float_double = function(T1,T2) return true end
    --note that the input type names are concatenated and separated by an underscore.
 
    --now you can call:
    assert(is_convertible_to(int32, int64))
    assert(is_convertible_to(float, double))
    assert(is_convertible_to(int64, int32)==false)
    assert(is_convertible_to(double, float)==false)
``` 
--]]
local function concept(arg)
    local name
    local default
    if terralib.types.istype(arg) then
        name = arg.name
        default = function(T) return T.name==name end
    elseif type(arg)=="string" then
        name = arg
        default = function(T) return false end
    else
        error("Specify name as a table entry or as an input string.", 2)
    end
    
    --construct main type representing a convept
    local self = terralib.types.newstruct(name)
    rawset(self, "default", default)
    rawset(self, "name", name)
    rawset(self, "type", "concept")
    self.definitions = {}

    --metatable for self
    local mt = getmetatable(self)

    --overload the call operator to make the table act
    --as a functor
    function mt:__call(...)
        local args = {...}
        if #args==1 and args[1]==self then
            --if input is the same as concept, then return true
            --directly
            return true
        end
        local signature = {}
        --extract type-property of each input
        for i,arg in ipairs(args) do
            signature[i] = arg.name
        end
        --concatenate type-properties
        local s = table.concat(signature, "_")
        --call the correct method
        return (self.definitions[s] or self.default)(...)
    end

    --custom method for adding method definitions
    function self:adddefinition(key, method)
        assert(type(method)=="function")
        self.definitions[key] = method
    end
    -- Overloading the < and > operators does not currently work in terra, because 
    -- terra is based on LuaJIT 2.1, for which extensions with __lt and __le are 
    -- turned of by default. LuaJIT needs to be built using 
    -- <DLUAJIT_ENABLE_LUA52COMPAT>, see https://luajit.org/extensions.html
    -- instead we introduce the following two methods
    function self:subtypeof(other)
        return other(self) and not self(other)
    end
    function self:supertypeof(other)
        return self(other) and not other(self)
    end

    --return table
    return self
end

concepts.concept = concept

return concepts