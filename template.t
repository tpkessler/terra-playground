-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concept = require("concept")
local base = require("base")
local fun = require("fun")

local Template = {}

local function sgn(x)
	return x > 0 and 1 or x < 0 and -1 or 0
end

local function printtable(tab)
	for k,v in pairs(tab) do
		print(k)
		print(v)
		print()
	end
end

function Template:new()
	local template = {
		-- Stores implementations for different concepts
		methods = {},
		-- Default behavior for arbitrary arguments
		default = function(...) return error("Implementation missing", 2) end,
		type = "template",
	}

    -- Check if method signature satisfies method concepts.
    -- This is used to rule out methods, such that only admissable methods remain.
    local function concepts_check(sig, args)
		if #sig~=#args then
			return false
		end
		local res = fun.all(function(C, T)
								return concept.has_implementation(C, T)
							end, fun.zip(sig, args))
		return res
	end

	-- Given two lists of concepts this function returns
	-- -1 if the second argument is more specialized,
	-- +1 if the first  argument is more specialized,
	--  0 if the signatures are ambiguous.
	local function compare_two_methods(clist_1, clist_2)
		assert(#clist_1 == #clist_2,
			   "Can only compare function signatures of equal size")
		local function compare(s, c_1, c_2)
			if concept.is_specialized_over(c_1, c_2) then
				s[1] = s[1] + 1
			end
			if concept.is_specialized_over(c_2, c_1) then
				s[2] = s[2] + 1
			end
			return s
		end
		local res = fun.foldl(compare, {0, 0}, fun.zip(clist_1, clist_2))
		return sgn(res[1] - res[2])
	end
	
	local formsig = function(uniqueparams, pos)
		local sig = terralib.newlist()
		for k,v in ipairs(pos) do
			sig:insert(uniqueparams[v])
		end
		return sig
	end


    -- Return a table of admissable methods.
	function template:get_methods(...)
		local args = {...}
		-- Only check input arguments. We can't control the return type
		-- when we do method dispatching.
		return fun.filter(function(sig, func)
							local s = formsig(sig[1], sig[2])
							return concepts_check(s, args)
						end,
						self.methods
						)
						-- For later comparison we only return the function
						-- parameters but not its return type.
						:map(function(sig, func) return sig, func end)
						:tomap()
	end

	function template:select_method(...)
		local args = {...}
		local admissible = self:get_methods(...)
		-- Matches every concept
		local Any = concept.Any
		local saved = {terralib.newlist(), terralib.newlist()}
		for i = 1, #args do
			saved[1]:insert(Any)
			saved[2]:insert(i)
		end
		local function minimal(acc, sig, func)
			local s = compare_two_methods(formsig(sig[1], sig[2]), formsig(acc[1], acc[2]))
			if s > 0 then -- sig is more specialized
				return sig
			else
				return acc
			end
		end
		-- Find minimal, most specialized implementation
		saved = fun.foldl(minimal, saved, admissible)
		--find all methods that reach same minimum
		local function ambiguous(sig, func)
			return 0 == compare_two_methods(formsig(sig[1], sig[2]), formsig(saved[1], saved[2]))
		end
		local methods = fun.filter(ambiguous, admissible):tomap()
		--there may still be some ambiguous methods, but some of these may
		--lead to casts
		local function nocasts(args, pos)
			for i,v in ipairs(pos) do
				if args[i]~=args[v] then
					return false
				end
			end
			return true
		end
		--if there are still ambiguous methods try reducing the methods 
		--to one candidate by comparing concrete types against the 'pos' array
		--evaluate to true if: args[i] == args[pos[i]] for all arguments
		if fun.length(methods) > 1 then
			for sig,func in pairs(methods) do
				if not nocasts(args, sig[2]) then
					methods[sig] = nil
				end
			end
		end
		--remaining methods are all valid methods that do not lead 
		--to casts
		--now select the method with minimal unique constraint list
		if fun.length(methods) > 1 then
			local sig, func = next(methods)
			for s,f in pairs(methods) do
				if #s[1] < #sig[1] then
					sig, func = s, f
				end
			end
			for s,f in pairs(methods) do
				if #s[1] > #sig[1] then
					methods[s] = nil
				end
			end
		end
		return methods
	end

	local mt = {}
	function mt:__newindex(key, value)
		--assert(terralib.types.istype(key) and key:ispointertofunction(),
		--	"Need to pass function pointer but got " .. tostring(key))
		--key = key.type
		self.methods[key] = value
	end

	function mt:__call(...)
		local args = terralib.newlist{...}
		local methods = self:select_method(unpack(args))
		if fun.length(methods) == 1 then
			local sig, func = next(methods)
			return (func or self.default)(...)
		else
			--throw an ambiguity error
			local err_str = ""
			err_str = err_str
				.. "The following method calls are ambiguous:\n"
			-- terralist has a nice tostring method
			local arg = terralib.newlist({...})
			err_str = err_str
				.. string.format("For signature %s there's\n", tostring(arg))
			for sig, func in pairs(methods) do
				err_str = err_str
					.. tostring(terralib.newlist(sig)) .. "\n"
			end
        	return error("Method call is ambiguous.\n" .. err_str, 2)
		end
	end

	return setmetatable(template, mt)
end

local function istemplate(T)
	return type(T) == "table" and T.type == "template"
end

local function dispatch(T, ...)
    return T.templates.eval(...)
end

local functiontemplate = function(name, methods)
    local T = terralib.types.newstruct(name)
    base.AbstractBase(T)
    T.templates.eval = Template:new("eval")
    T.metamethods.__apply = macro(function(self, ...)
        local args = terralib.newlist({...})
        local typs = args:map(function(a) return a:gettype() end)
        local func = dispatch(T, unpack(typs))
        return `func([args])
    end)

    local t = constant(T)
    function t:adddefinition(methods)
		methods = methods or {}
        for sig, func in pairs(methods) do
            T.templates.eval[sig] = func
        end
    end
    function t:dispatch(...)
        return dispatch(T, ...)
    end

	t:adddefinition(methods)

    return t
end

return {
	Template = Template,
	functiontemplate = functiontemplate,
	istemplate = istemplate,
}

