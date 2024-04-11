local List = require("terralist")

local function has_key(tab, key)
	for k, _ in pairs(tab) do
		if k == key then
			return true
		end
	end
	return false
end

local function get_entry(tabt, key)
	for _, v in pairs(tabt) do
		if key == v.field then
			return v.field, v.type
		end
	end
	return nil
end

local struct AbstractSelf
local function Interface(S)
	local ref_entries = {}
	local ref_methods = {}
	for k, v in pairs(S) do
		assert(terralib.types.istype(v),
			   "Value of " .. k .. " must be a terra type")
		if v:ispointertofunction() then
			assert(v.type.parameters[1] == &AbstractSelf,
				   "Interface methods must use the abstract self type ".. 
				   "as their argument.")
			ref_methods[k] = v
		else
			ref_entries[k] = v
		end
	end

	local I = {}

	function I:isimplemented(T)
		assert(T:isstruct(),
			   "Given type for interface is not a struct")
		local T_entries = T:getentries()
		for ref_name, ref_type in pairs(ref_entries) do
			local T_name, T_type = get_entry(T_entries, ref_name)
			assert(T_name == ref_name, "Cannot find struct entry named " .. ref_name)
			assert(T_type == ref_type, "Wrong type for entry " .. ref_name .. ".\n" ..
									   "Expected " .. tostring(ref_type) ..
									   " but got " .. tostring(T_type))
		end

		local T_methods = T.methods
		for ref_name, ref_method in pairs(ref_methods) do
			assert(has_key(T_methods, ref_name),
				   "Missing method called " .. ref_name)
			local T_method = T_methods[ref_name]
			-- Cast abstract interface method to specific type self.
			-- This is always a pointer to T.
			local cast_parameters = {}
			local ref_parameters = ref_method.type.parameters
			for i = 1, #ref_parameters do
				local param = ref_parameters[i]
				if param == &AbstractSelf then
					cast_parameters[i] = &T
				else
					cast_parameters[i] = ref_parameters[i]
				end
			end
			-- From the updated parameter list, build the corresponding
			-- function signature to check against the provided implementation.
			--
			-- Convert the general lua table to a terralist to force all elements
			-- of the parameter list to be of type "Type", see
			-- https://github.com/terralang/terra/blob/4d32a10ffe632694aa973c1457f1d3fb9372c737/src/terralib.lua#L1148
			-- TODO support vararg, see last argument
			local cast_method = terralib.types.functype(List{unpack(cast_parameters)},
													    ref_method.type.returntype,
													    false)

			if terralib.isoverloadedfunction(T_method) then
				local has_matching_overload = false
				for _, implemented in pairs(T_method.definitions) do
					if implemented.type == cast_method then
						has_matching_overload = true
						break
					end
				end

				if has_matching_overload == false then
					error("Overloaded method " .. T_method.name ..
						  " has no implementation for " .. tostring(cast_method))
				end
			else
				assert(T_method.type == cast_method,
					   "Wrong type for method " .. ref_name .. ".\n" ..
					   "Expected " .. tostring(cast_method) ..
					   " but got " .. tostring(T_method.type))
			end
		end
	end

	return I
end

return {Interface, AbstractSelf}
