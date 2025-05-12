-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concepts = require("concept-impl")

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
		local Self = terralib.types.newstruct("Self" .. tostring(T))
		concepts.Base(Self)
		for key, val in pairs({staticmethods = {}, templates = {}, varargtemplates = {}, Self = Self, traits = {}}) do
			T[key] = val
		end
		Self.methods = T.methods
		Self.staticmethods = T.staticmethods
		Self.templates = T.templates

		T.metamethods.__getmethod = function(self, methodname)
		    local fnlike = self.methods[methodname]
			--try staticmethods table
			if not fnlike then
				fnlike = T.staticmethods[methodname]
				--detect name collisions with T.tempplates
				if fnlike and T.templates[methodname] then
					return error("NameCollision: Function " .. methodname .. " defined in ".. 
									tostring(T) .. ".templates and " .. tostring(T) ..".staticmethods.")
				end
			end
			--if no implementation is found try __methodmissing
		    if not fnlike and terralib.ismacro(self.metamethods.__methodmissing) then
		        fnlike = terralib.internalmacro(function(ctx, tree, ...)
		            return self.metamethods.__methodmissing:run(ctx, tree, methodname, ...)
		        end)
		    end
		    return fnlike
		end

		T.metamethods.__methodmissing = macro(function(name, obj, ...)
			assert(obj.tree.type == T) --__methodmissing should only be called for 
			--class methods, not for static methods
			local args = terralib.newlist{...}
			local types = args:map(function(t) return t.tree.type end)
			types:insert(1, &T)
			local method = T.templates[name]
			if method then
				local sig, func = method(unpack(types))
				if func then
					if not sig:isvararg() then
						--regular template dispatch
						return `[func](&obj, [args])
					else
						--variable argument dispatch
						local newargs, varargs = terralib.newlist(), terralib.newlist()
						local m = sig:len()-2 --sig includes concepts Vararg and Self. Therefore we subtract 2.
						for k = 1, m do
							newargs:insert(args[k])
						end 
						for k = m+1,#args do
							varargs:insert(args[k])
						end
						return `[func](&obj, [newargs], {[varargs]})
					end
				end
			end
			error(
				(
					"Cannot find implementation for method %s on type %s" ..
					" for argument %s"
				):format(name, tostring(T), tostring(types))
			)
		end)
	end
)

return {
	Base = Base,
	AbstractBase = AbstractBase
}
