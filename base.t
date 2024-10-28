-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

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
		local Self = concept.Concept:new("Self" .. tostring(T))
		Self:addimplementations{T}
		for key, val in pairs({staticmethods = {}, templates = {}, Self = Self}) do
			if T.key == nil then
				rawset(T, key, val)
			end
		end
		Self.methods = T.methods
		Self.staticmethods = T.staticmethods
		Self.templates = T.templates

		T.metamethods.__getmethod = function(self, methodname)
		    local fnlike = self.methods[methodname] or self.staticmethods[methodname]
		    if not fnlike and terralib.ismacro(self.metamethods.__methodmissing) then
		        fnlike = terralib.internalmacro(function(ctx, tree, ...)
		            return self.metamethods.__methodmissing:run(ctx, tree, methodname, ...)
		        end)
		    end
		    return fnlike
		end

		T.metamethods.__methodmissing = macro(function(name, obj, ...)
			local args = terralib.newlist{...}
			local types = args:map(function(t) return t.tree.type end)
			local method = T.templates[name]
			if obj.tree.type == T then
				--case of a class method
				types:insert(1, &T)
				local func = method(unpack(types))
				return `[func](&obj, [args])
			else
				--case of a static method
				types:insert(1, obj.tree.type)
				local func = method(unpack(types))
				return `[func](obj, [args])
			end
		end)
	end
)

return {
	Base = Base,
	AbstractBase = AbstractBase
}
