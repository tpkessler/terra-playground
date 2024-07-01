local concept = require("concept")

local Base = {}

function Base:new(name, func)
	local base = {name = name}
	setmetatable(base, {__index = self})

	local mt = getmetatable(base)

	function mt:__call(T)
		func(T)
	end

	function mt.__mul(B1, B2)
		local function impl(T)
			B1(T)
			B2(T)
		end
		return Base:new(B1.name .. "And" .. B2.name, impl)
	end

	return base
end

local AbstractBase = Base:new("AbstractBase",
	function(T)
		assert(terralib.types.istype(T))
		assert(T:isstruct())
		local Self = concept.Concept:new(tostring(T),
										 function(Tp) return Tp.name == T.name end
										) 
		for key, val in pairs({static_methods = {}, templates = {}, Self = Self})  do
			if T.key == nil then
				rawset(T, key, val)
			end
		end

		T.metamethods.__methodmissing = macro(function(name, obj, ...)
			local is_static = (S.static_methods[name] ~= nil)
			local args = terralib.newlist({...})
			if is_static then
				args:insert(1, obj)
			end
			local types = args:map(function(t) return t.tree.type end)
			if is_static then
				local method = S.static_methods[name]
				return `method([args])
			else
				types:insert(1, &S)
				local method = S.templates[name]
				local func = method(unpack(types))
				return quote [func](&obj, [args]) end
			end
		end)
	end
)

return {
	Base = Base,
	AbstractBase = AbstractBase
}
