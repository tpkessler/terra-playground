-- Start with an empty cache
local Interface = {cached = terralib.newlist()}

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
		Interface{
				size = {} -> int64,
				get = {int64} -> double,
				set = {int64, double} -> {}
		}

		is an abstract interface for a stack with given size on which we can
		define setter an getter methods for element access.
--]]
function Interface:new(methods)
	methods = methods or {}
	local interface = {methods = terralib.newlist()}
	setmetatable(interface, {__index = self})
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
		interface.methods:insert({name = name, type = method.type})
		vtable.entries:insert({field = name, type = &opaque})
	end

	-- Second iteration for method wrappers
	for _, method in pairs(interface.methods) do
		-- Write a dynamic wrapper around the method call.
		-- A method call on the wrapper struct mirrors the method call on the
		-- concrete type.
		local param = terralib.newlist{&opaque} -- First argument is always self
		local sym = terralib.newlist()
		-- Loop over arguments of the interface interface and prepare lists
		-- for the meta programmed method call.
		for _, typ in ipairs(method.type.parameters) do
			param:insert(typ)
			sym:insert(symbol(typ))
		end
		-- This function implements the method call of the concrete type
		-- on the dummy wrapper type. Here, the self object is replaced
		-- with the wrapper object such that we can access both the vtable
		-- with the function pointers to the concrete implementation
		-- and the concrete underlying data representation of the type.
		-- Both are passed as opaque pointers and need to be cast first.
		local signature = param -> method.type.returntype
		local terra impl(self: &wrapper, [sym])
			var func = [signature](self.tab.[method.name])
			return func(self.data, [sym])
		end

		wrapper.methods[method.name] = impl
	end

	-- Cast from an abstract interface to a concrete type
	function wrapper.metamethods.__cast(from, to, exp)
		-- TODO Implement caching
		if to:isstruct() and from:ispointertostruct() then
			assert(interface:isimplemented(from.type))
			assert(to == wrapper)
			local impl = terralib.newlist()
			-- interface.methods is ordered like vtable
			for _, method in ipairs(interface.methods) do
				impl:insert(from.type.methods[method.name])
			end
			-- The built-in function constant forces the expression to be an lvalue,
			-- so we use its address in the construction of the wrapper.
			local tab = constant(`vtable { [impl] })
			return `wrapper { [&opaque](exp), &tab }
		end
	end

	interface.type = wrapper
	return interface
end

-- Check if the interface is implemented on a given type
function Interface:isimplemented(T)
	assert(T:isstruct(), "Can't check interface implementation as " ..
						 "type " .. tostring(T) .. " is not a struct")
	for _, method in pairs(self.methods) do
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
			   " for method" .. method.name)
	end

	return true
end

local I = Interface:new{
	size = {} -> int64,
	get = {int64} -> double,
	set = {int64, double} -> {}
}

local J = Interface:new{
	size = {} -> int64,
	get = {int64} -> double,
	set = {int64, double} -> {}
}

local struct A {}
terra A:size(): int64 return 1 end
terra A:get(i: int64) return 1.3 end
terra A:set(i: int64, a: double) end

local struct B {}
terra B:size(): int64 return 2 end
terra B:get(i: int64) return -0.33 end
terra B:set(i: int64, a: double) end

terra foo(a: I.type)
	return 2 * a:get(0)
end

local io = terralib.includec("stdio.h")
terra main()
	var a: A
	var b: B

	io.printf("for A it's %g\n", foo(&a))
	io.printf("for B it's %g\n", foo(&b))
end

main()

return {
	Interface = Interface
}
