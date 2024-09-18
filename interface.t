-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local serde = require("serde")
local fun = require("fun")

local Interface = {}

local construct_wrapper = terralib.memoize(function(methods_str)
	--[=[
		Helper function to cache terra interface types.

		Terra types are lua tables and can thus not be memoized by terralib.
		We hence convert the interface into a unique string representation
		from which we can recover its terra representation that is then used
		in the construction of the terra types.
	--]=]
	local ok, obj = serde.deserialize_table(methods_str)
	assert(ok)
	local methods = fun.map(function(name, str)
								return name, serde.deserialize_pointertofunction(str)
							end,
							obj
						   ):tomap()
	-- A vtable contains function pointers to the implementation of methods
	-- defined on a concrete type that implements the given interface.
	-- With terra we can dynamically build the struct at compile time.
	-- These function pointers are stored as opaque pointers and will be cast
	-- to the concrete implementation only when the method is called.
	local vtable = terralib.types.newstruct("vtable")
	-- Keep information on the underlying data as an opaque pointer
	-- together with a lookup table for methods.
	-- The actual cast to the underlying data is done in methods defined
	-- on this struct.
	local struct wrapper{
			data: &opaque
			tab:  &vtable
	}

	-- First implement all fields of the type, then iterate a second
	-- time to generate the wrapper code
	for name, method in pairs(methods) do
		assert(method:ispointer() and method.type:isfunction(),
				 "Interface takes table of function pointers but got " ..
				 string.format("%s for key %s", tostring(method), name))
		-- Add entries of the struct to a separate table so we can initialize
		-- the struct from a list with the same ordering, see __cast.
		vtable.entries:insert({field = name, type = &opaque})
	end
	vtable:complete()

	-- Second iteration for method wrappers
	for name, func in pairs(methods) do
		-- Write a dynamic wrapper around the method call.
		-- A method call on the wrapper struct mirrors the method call on the
		-- concrete type.
		local param = terralib.newlist{&opaque} -- First argument is always self
		local sym = terralib.newlist()
		-- Loop over arguments of the interface and prepare lists
		-- for the meta programmed method call.
		for _, typ in ipairs(func.type.parameters) do
			param:insert(typ)
			sym:insert(symbol(typ))
		end
		-- This function implements the method call of the concrete type
		-- on the dummy wrapper type. Here, the self object is replaced
		-- with the wrapper object such that we can access both the vtable
		-- with the function pointers to the concrete implementation
		-- and the concrete underlying data representation of the type.
		-- Both are passed as opaque pointers and need to be cast first.
		local signature = param -> func.type.returntype
		local terra impl(self: &wrapper, [sym])
			var func = [signature](self.tab.[name])
			return func(self.data, [sym])
		end

		wrapper.methods[name] = impl
	end

	return {wrapper, vtable}
end)

function Interface:new(methods)
	--[[
		Construct an interface with given methods.

		Given a list of methods, that is a table of function pointers,
		construct a wrapper struct to dynamically (at compile time) call the
		implementation on the concrete type. The self object as first object
		must not be specified in the function pointer but is added automatically.

		Args:
			methods: Table of function pointers that define the interface

		Returns:
			Interface to be used as an abstract type in terra function signatures.

		Example:
			Interface:new{
					size = {} -> int64,
					get = {int64} -> double,
					set = {int64, double} -> {}
			}

			is an abstract interface for a stack with given size on which we can
			define setter an getter methods for element access.
	--]]
	methods = methods or {}
	local method_str = {} 
	for name, method in pairs(methods) do
		method_str[name] = serde.serialize_pointertofunction(method)
	end
	local wrapper, vtable = unpack(construct_wrapper(serde.serialize_table(method_str)))
	rawset(wrapper, "type", "interface")
	-- Store reference methods without the &self parameter in the beginning
	-- for easier checks if a given struct implements the interface.
	rawset(wrapper, "ref_methods", terralib.newlist())
	for name, method in pairs(methods) do
		wrapper.ref_methods:insert({name = name, type = method.type})
	end

	function wrapper:isimplemented(T)
		assert(T:isstruct(), "Can't check interface implementation as " ..
							 "type " .. tostring(T) .. " is not a struct")
		for _, method in pairs(self.ref_methods) do
			local T_method = T.methods[method.name]
			assert(T_method and T_method.type:isfunction(),
				   "Method " .. method.name .. " is not implemented for type " .. tostring(T))
			local ref_param = terralib.newlist{&T}
			for _, p in ipairs(method.type.parameters) do
				ref_param:insert(p)
			end
			local ref_method = ref_param -> method.type.returntype
			assert(T_method.type == ref_method.type,
				   "Expected signature " .. tostring(ref_method.type) ..
				   " but found " .. tostring(T_method.type) ..
				   " for method " .. method.name)
		end

		return true
	end

	-- Cast from an abstract interface to a concrete type
	function wrapper.metamethods.__cast(from, to, exp)
		if to:isstruct() and from:ispointertostruct() then
			assert(wrapper:isimplemented(from.type))
			assert(to == wrapper)
			-- Now we initialize the vtable with pointers to
			-- the actual methods for type from.
			-- IMPORTANT: When setting up vtable struct we fixed
			-- a particular ordering of the methods.
			-- We need to iterate in the exact same ordering,
			-- otherwise the function pointers in impl will
			-- point to the wrong functions.
			local impl = terralib.newlist()
			for _, entry in ipairs(vtable:getentries()) do
				impl:insert(from.type.methods[entry.field])
			end
			-- The built-in function constant forces the expression to be
			-- an lvalue, so we use its address in the construction
			-- of the wrapper.
			local tab = constant(`vtable {[impl]})
			return `wrapper {[&opaque](exp), &tab}
		end
	end

	return wrapper
end

local function isinterface(I)
	return I.type == "interface"
end

-- Check if the interface is implemented on a given type
return {
	Interface = Interface,
	isinterface = isinterface
}
