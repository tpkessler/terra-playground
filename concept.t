-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local fun = require("fun")

local shim_concept = terralib.memoize(function(name)
	local concept = terralib.types.newstruct(name)
	rawset(concept, "type", "concept")
	rawset(concept, "name", name)
	rawset(concept, "implementations", {})
	return concept
end)

local Concept = {}
function Concept:new(name, custom_check)
	assert(name, "Give a name for the concept!")
	local concept = shim_concept(name)
	concept.superconcepts = {}

	local mt = getmetatable(concept)

	function mt:getimplementations()
		return self.implementations
	end

	function mt:addimplementations(impl)
		for _, T in pairs(impl) do
			self.implementations[T] = true
		end
	end

	function mt:addfrom(C)
		self:addimplementations(fun.map(function(T, v) return T end,
								C:getimplementations()
							   ):totable())
	end

	local function default_check(self, T)
		for S, _ in pairs(self:getimplementations()) do
			if S == T then
				return true
			end
		end
		return false
	end
	concept.check = custom_check or default_check

	function concept:setcheck(custom_check)
		self.check = custom_check
	end

	function mt:__call(...)
		return self.check(self, ...)
	end

	return concept
end

local function isconcept(C)
	return terralib.types.istype(C) and C.type == "concept"
end

local Any = Concept:new("Any", function(...) return true end)

local function is_specialized_over(C1, C2)
	for _, C in pairs({C1, C2}) do
		assert(terralib.types.istype(C),
			"Argument " .. tostring(C) .. " is not a terra type!")
	end

	-- The Any concept can only be more specialized
	-- if compared to the Any concept.
	if C1 == Any then
		if C2 == Any then
			return true
		else
			return false
		end
	end

	-- Every concept is more specialized then the Any concept.
	if C2 == Any then
		return true
	end

	-- Checks can fail if the concept is empty,
	-- as it can happen in self-referencing abstract interfaces,
	-- so we skip all checks and return true directly.
	if C1 == C2 then
		return true
	end

	if C1:ispointer() and C2:ispointer() then
		return is_specialized_over(C1.type, C2.type)
	elseif C1:ispointer() or C2:ispointer() then
		error("Can only compare two pointers to concepts but given\n"
			  .. tostring(C1) .. " and " .. tostring(C2))
	end

	-- If C1 inherits properties of C2, it is always specialized over C2.
	if C1.superconcepts[C2] then
		return true
	elseif C2.superconcepts[C1] then
		return false
	end

	local ret = false
	for T, _ in pairs(C1:getimplementations()) do
		ret = ret or C2(T)
		if not ret then
			return false
		end
	end
	return ret
end

local function has_implementation(C, T)
	assert(terralib.types.istype(C) and terralib.types.istype(T))
	if C:ispointer() and T:ispointer() then
		--dereference pointer types
		return has_implementation(C.type, T.type)
	elseif isconcept(C) then
		--in case C is a concept
		return C(T)
	else
		--in case C is a concrete type
		return C==T
	end
end

local AbstractInterface = {}
function AbstractInterface:new(name, ref_methods)
	ref_methods = ref_methods or {}

	local interface = Concept:new(name)
	interface.superconcepts = {}

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

	function interface:inheritfrom(C)
		interface.superconcepts[C] = true
		for k, _ in pairs(C.superconcepts or {}) do
			interface.superconcepts[k] = true
		end
		local function drop_self(ptr)
			local par = {}
			for i, k in ipairs(ptr.type.parameters) do
				if i > 1 then
					par[#par + 1] = k
				end
			end
			return par -> ptr.type.returntype
		end
		for name, method in pairs(C.methods) do
			self:addmethod{[name] = drop_self(method)}
		end
	end

	local function is_self(Tref, Tcheck)
		if Tref == Tcheck then
			return true
		elseif Tcheck:ispointer() then
			return is_self(Tref, Tcheck.type)
		else
			return false
		end
	end

	local function implements_interface(self, T)
		if not T:isstruct() then
			return false
		end
		local function has_implementation(C, S)
			print(C)
			print(S)
			print()
			if isconcept(C) and isconcept(S) then
				return is_specialized_over(S, C)
			elseif isconcept(C) and terralib.types.istype(S) then
				return C(S)
			else
				error("Cannot compare", C, "and", S)
			end
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
						return is_self(T, S) or has_implementation(C, S)
					end
				end
				-- Check all but the first parameter, the reference to self.
				local res = fun.all(go, fun.zip(ref_sig.parameters,
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

	interface:setcheck(implements_interface)

	return interface
end

local M = {
	Concept = Concept,
	AbstractInterface = AbstractInterface,
	isconcept = isconcept,
	has_implementation = has_implementation,
	is_specialized_over = is_specialized_over
}

M.Any = Any
M.Bool = Concept:new("Bool")
M.Bool:addimplementations{bool}
M.RawString = Concept:new("RawString")
M.RawString:addimplementations{rawstring}

M.Float = Concept:new("Float") 
for suffix, T in pairs({["32"] = float, ["64"] = double}) do
	local name = "Float" .. suffix
	M[name] = Concept:new(name)
	M[name]:addimplementations{T}
	M.Float:addimplementations{T}
end

for _, prefix in pairs({"", "u"}) do
	local cname = prefix:upper() .. "Integer"
	M[cname] = Concept:new(cname)
	for _, suffix in pairs({8, 16, 32, 64}) do
		local name = prefix:upper() .. "Int" .. tostring(suffix)
		local terra_name = prefix .. "int" .. tostring(suffix)
		-- Terra primitive types are global lua variables
		local T = _G[terra_name] 
		M[name] = Concept:new(name)
		M[name]:addimplementations{T}
		M[cname]:addimplementations{T}
	end
end

M.Real = Concept:new("Real")
for _, C in pairs({M.Float, M.Integer}) do
	M.Real:addfrom(C)
end

M.Complex = Concept:new("Complex")

M.Number = Concept:new("Number")
for _, C in pairs({M.Float, M.Integer, M.UInteger}) do
	M.Number:addfrom(C)
end

M.BLASNumber = Concept:new("BLASNumber")
M.BLASNumber:addimplementations{float, double}

M.Primitive = Concept:new("Primitive")
for _, C in pairs({M.Integer, M.UInteger, M.Bool, M.Float}) do
	M.Primitive:addfrom(C)
end
M.Integral = Concept:new("Integral")
for _, C in pairs({M.Integer, M.UInteger}) do
	M.Integral:addfrom(C)
end

return M
