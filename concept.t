--[[
A 'concept' defines an equivalence class, that is, a set with an equivalence relation by which objects in the set may be compared. Each concept is a table that behaves like a lua function object: a boolean predicate. A function call yields a boolean value that signals that the input belongs to the equivalence class or not.
```docexample
    --create a concept 'c = Concept:new(<name>, <default>)' where <name> is a string, e.g.
    local Integer = Concept:new("Integer")

	-- and <default> defines its default behavior,
    Integer.default = function(T) return tostring(T) == "Integer" end

	-- If <name> is a terra type, then defaults are set automatically,
    Integer.int32 = function return true end
    Integer.int64 = function return true end
    --the notation Integer.<name> is used to perform method selection.
	-- Terra's primitive types have a .name property. For example int32.name == "int32".
    
    --now you can call:
    assert(Integer(Integer))
    assert(Integer(int32))
    assert(Integer(int64))
    assert(Integer(double)==false)

    --create concepts for concrete terra types. Proper defaults are automatically
	--handled as long as the terra objects have a tostring() method.
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
    local is_convertible_to = Concept:new("is_convertible_to", function(T1, T2) return false end)

    --Define the equivalence relation
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
local interface = require("interface")
local fun = require("fun")

local shim_concept = terralib.memoize(function(name)
	local concept = terralib.types.newstruct(name)
	rawset(concept, "type", "concept")
	rawset(concept, "name", name)
	rawset(concept, "definitions", {})
	return concept
end)

local Concept = {}
function Concept:new(arg, default)
    local name
    if terralib.types.istype(arg) then
		name = tostring(arg)
        default = default or function(T) return T == arg end
    elseif type(arg) == "string" then
        name = arg
        default = default or function(T) return false end
    else
        error("Specify name as a table entry or as an input string.", 2)
    end
	local concept = shim_concept(name)
	rawset(concept, "default", default)

	function concept:setdefault(new_default)
		self.default = new_default
	end

    local mt = getmetatable(concept)
    --overload the call operator to make the struct act as a functor
    function mt:__call(...)
        local args = {...}
        if #args == 1 and args[1] == self then
            return true
		end
        local signature = {}
        for i, arg in ipairs(args) do
            signature[i] = tostring(arg)
        end
        local s = table.concat(signature, "_")
        return (self.definitions[s] or self.default)(...)
    end

	function mt.__add(C1, C2)
		local C = Concept:new(C1.name .. "Or" .. C2.name,
							  function(...) return C1(...) or C2(...) end)
		return C
	end

	function mt.__mul(C1, C2)
		local C = Concept:new(C1.name .. "And" .. C2.name,
							  function(...) return C1(...) and C2(...) end)
		return C
	end

	function mt.__div(C1, C2)
		local C = Concept:new(C1.name .. "Div" .. C2.name,
							  function(...) return C1(...) and not C2(...) end)
		return C
	end

    --custom method for adding method definitions
    function concept:adddefinition(key, method)
        assert(type(method) == "function")
        concept.definitions[key] = method
    end
    -- Overloading the < and > operators does not currently work in terra, because 
    -- terra is based on LuaJIT 2.1, for which extensions with __lt and __le are 
    -- turned of by default. LuaJIT needs to be built using 
    -- <DLUAJIT_ENABLE_LUA52COMPAT>, see https://luajit.org/extensions.html
    -- instead we introduce the following two methods
    function concept:subtypeof(other)
        return other(self) and not self(other)
    end
    function concept:supertypeof(other)
        return self(other) and not other(self)
    end

    return concept
end

function Concept:from_interface(name, I)
	assert(interface.isinterface(I))
	local check_interface = function(T)
		local ok, ret = pcall(
			function(Tprime)
				local U = Tprime:ispointer() and Tprime.type or Tprime
				return I:isimplemented(U)
			end, T)
		return ok
	end
	return Concept:new(name, check_interface)
end

local function isconcept(C)
	return terralib.types.istype(C) and C.type == "concept"
end

local AbstractInterface = {}
function AbstractInterface:new(name, ref_methods)
	ref_methods = ref_methods or {}

	local interface = Concept:new(name)

	function interface:addmethod(methods)
		local function prepend_self(ptr)
			local par = {&interface}
			for i, k in ipairs(ptr.type.parameters) do
				par[i + 1] = k
			end
			return par -> ptr.type.returntype
		end

		for method, ptr in pairs(methods) do
			assert(interface.methods[method] == nil,
				   "The method " .. method .. " is already defined in " ..
				   self.name)
			assert(terralib.types.istype(ptr)
				   and ptr:ispointertofunction(),
				   "Need to pass a function pointer but got " .. tostring(ptr))
			self.methods[method] = prepend_self(ptr)
		end
	end

	interface:addmethod(ref_methods)

	local function is_self(Tref, Tcheck)
		if Tref == Tcheck then
			return true
		elseif Tcheck:ispointer() then
			return is_self(Tref, Tcheck.type)
		else
			return false
		end
	end

	local function implements_interface(T)
		if not T:isstruct() then
			return false
		end
		local function is_implemented(sig, ref_sig)
			if #sig.parameters ~= #ref_sig.parameters then
				return false
			else
				local function go(C, S)
					if C:ispointer() then
						if not S:ispointer() then
							return false
						else
							return go(C.type, S.type)
						end
					else
						return is_self(T, S) or C(S)
					end
				end
				-- Check all but the first parameter, the reference to self.
				local res = fun.all(go,
											fun.zip(ref_sig.parameters,
															sig.parameters
														 ):tail())
				-- Ignore return values as we don't have control over them
				-- during the concept dispatching for templates.
				return res
			end
		end

		local function check_method(name, ref_sig)
			if T.methods[name] then
				return is_implemented(T.methods[name].type, ref_sig.type)
			else
				return false
			end
		end

		local function check_template(name, ref_sig)
			if T.templates == nil then
				return false
			else
				if T.templates[name] then
					local methods = T.templates[name].methods
					local res = fun.any(function(sig)
											return is_implemented(sig, ref_sig.type)
										end,
										fun.map(function(k, v) return k end,
												methods)
										)
					return res
				else
					return false
				end
			end
		end

		local res = fun.all(function(name, ref_sig)
								return check_method(name, ref_sig)
									   or check_template(name, ref_sig)
							end, interface.methods)
		return res
	end

	interface:setdefault(implements_interface)

	return interface
end

local Ptr = terralib.memoize(function(C)
	assert(isconcept(C), "Argument for pointer factory has to be a concept")
	local function check(T)
		if not T:ispointer() then
			return false
		else
			return C(T.type)
		end
	end
	local ptr = Concept:new("&" .. C.name, check)

	return ptr
end)

local M = {
	Concept = Concept,
	AbstractInterface = AbstractInterface,
	Ptr = Ptr,
	isconcept = isconcept
}

M.Any = Concept:new("Any", function(...) return true end)
M.Bool = Concept:new("Bool", function(T) return T.name == "bool" end)
M.RawString = Concept:new(tostring(rawstring), function(T) return T.name == rawstring.name end)
M.Pointer = Concept:new("&Pointer", function(T) local name = T.name or tostring(T)
												if name ~= nil then
													return name:find("^&") ~= nil
												else
													return false
												end
											end)

M.Float = Concept:new("Float") 
for suffix, T in pairs({["32"] = float, ["64"] = double}) do
	local name = "Float" .. suffix
	M[name] = Concept:new(T)
	M.Float:adddefinition(T.name,
						  function(Tprime) return Tprime.name == T.name end
						 )
end

for _, prefix in pairs({"", "u"}) do
	local cname = prefix:upper() .. "Integer"
	M[cname] = Concept:new(cname)
	for _, suffix in pairs({8, 16, 32, 64}) do
		local name = prefix:upper() .. "Int" .. tostring(suffix)
		local terra_name = prefix .. "int" .. tostring(suffix)
		-- Terra primitive types are global lua variables
		local T = _G[terra_name] 
		M[name] = Concept:new(T)
		M[cname]:adddefinition(T.name,
							   function(Tprime) return Tprime.name == T.name end
							  )
	end
end

M.Real = Concept:new("Real", function(T) return false end)
M.Real:adddefinition(M.Integer.name, function(T) return M.Integer(T) end)
M.Real:adddefinition(M.Float.name, function(T) return M.Float(T) end)
M.Real = Concept:new("Real", function(T) return M.Integer(T) or M.Float(T) end)

M.Number = Concept:new("Number", function(T) return M.Real(T) end)
M.Primitive = M.Integer + M.UInteger + M.Bool + M.Float

return M
