-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concept = require("concept")
local base = require("base")
local fun = require("fun")
local serde = require("serde")

local Template = {}

printtable = function(tab)
	for k,v in pairs(tab) do
		print(k)
		print(v)
		print()
	end 
end


local function sgn(x)
	return x > 0 and 1 or x < 0 and -1 or 0
end

local function nref(tp,n)
	for k=1,n do
		tp = &tp
	end
	return tp
end

local function getunderlyingtype(tp)
	while tp:ispointer() do
		tp = tp.type
	end
	return tp
end

--representation of signature in terms of two tables,
--unique types and 
--{{T,S},{1,2,1}} = {T, S, T}
local paramlist = {}
--readonly table
paramlist.__newindex = function(t,k,v)
	error("Attempt to update a read-only table", 2)
end
--accessing values
paramlist.__index = function(t,k)
	if type(k)=="number" then
		return nref(t.keys[t.pos[k]], t.ref[k]) 
	else
		return paramlist[k] or rawget(t, k)
	end
end
--create a new parameter list from unique keys and position array
--{{T,S},{1,2,1}} = {T, S, T}
paramlist.new = function(keys, pos, ref)
	local t = {keys=keys, pos=pos, ref=ref}
	return setmetatable(t, paramlist)
end
--return parameter-list {Any,Any,...}
paramlist.init = function(n)
	assert(type(n) == "number")
	local keys, pos, ref = terralib.newlist(), terralib.newlist(), terralib.newlist()
	for i = 1, n do
		keys:insert(concept.Any)
		pos:insert(i)
		ref:insert(0)
	end
	return paramlist.new(keys, pos, ref)
end
--return iterator
function paramlist:iter(maxlen) --padd until maxlen with Any
	maxlen = maxlen or 0
	local i = 0
	local n = #rawget(self,"pos")
	return function()
		if i < n then
			i = i + 1
			return i, self[i]
		end
		if i < maxlen then
			i = i + 1
			return i, concept.Any
		end
	end
end
function paramlist:len()
	return #rawget(self,"pos")
end
function paramlist:isvararg()
	return self.keys[#self.keys] == concept.Vararg
end
paramlist.__tostring = function(t)
	local s = {}
	for k,v in t:iter() do
		table.insert(s, tostring(v))
	end
	return "{" .. table.concat(s, ", ") .. "}"
end
function paramlist:serialize()
	local s1 = tostring(self.keys)
	local s2 = tostring(self.pos)
	local s3 = tostring(self.ref)
	return s1 ..":" .. s2 .. ":" .. s3
end
function paramlist:collect(maxlen)
	local s = {}
	for k,v in self:iter(maxlen) do
		table.insert(s, v)
	end
	return s
end
function paramlist:signature()
	local parameters = self:collect()
	return parameters -> {}
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
		--input argument length needs to match the signature
		--unless we have a variable argument template
		if sig:isvararg() then
			if sig:len()>#args then
				return false
			end
		else
			if sig:len()~=#args then
				return false
			end
		end
		--get the expanded signature
		local expandedsig = sig:collect(#args)
		--check which methods are admissible
		local res = fun.all(function(C, T)
								return concept.is_specialized_over(T, C)
							end, fun.zip(expandedsig, args))
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

    -- Return a table of admissable methods.
	function template:get_methods(...)
		local args = {...}
		-- Only check input arguments. We can't control the return type
		-- when we do method dispatching.
		return fun.filter(function(sig, func)
							return concepts_check(sig, args)
						end,
						self.methods
						)
						-- For later comparison we only return the function
						-- parameters but not its return type.
						:tomap()
	end

	local function select_most_specialized(args, admissible)
		--if there is only one method then we are done
		if fun.length(admissible) == 1 then
			return admissible
		end
		--signature length used to expand variable argument definitions
		local siglength = #args
		-- Find minimal, most specialized implementation
		local function minimal(acc, sig, func)
			local s = compare_two_methods(sig:collect(siglength), acc:collect(siglength))
			if s > 0 then -- sig is more specialized
				return sig
			else
				return acc
			end
		end
		local saved = paramlist.init(#args)
		saved = fun.foldl(minimal, saved, admissible)
		--find all methods that reach same minimum
		local function ambiguous(sig, func)
			return 0 == compare_two_methods(sig:collect(siglength), saved:collect(siglength))
		end
		local methods = fun.filter(ambiguous, admissible):tomap()
		--there may still be some ambiguous methods, but some of these may
		--lead to casts. Try reducing the methods to one candidate by comparing 
		--concrete types against the 'pos' array
		local function requirescast(args, sig)
			for i,v in ipairs(sig.pos) do
				if getunderlyingtype(args[i])~=getunderlyingtype(args[v]) then
					return true
				end
			end
			return false
		end
		--remove candidate functions that lead to casts
		if fun.length(methods) > 1 then
			for sig,func in pairs(methods) do
				if requirescast(args, sig) then
					methods[sig] = nil
				end
			end
		end
		--remaining methods are all valid methods that do not lead 
		--to casts. Now select the method with minimal unique constraint list
		if fun.length(methods) > 1 then
			local sig, func = next(methods)
			for s,f in pairs(methods) do
				if #s.keys < #sig.keys then
					sig, func = s, f
				end
			end
			for s,f in pairs(methods) do
				if #s.keys > #sig.keys then
					methods[s] = nil
				end
			end
		end
		return methods
	end

	function template:select_method(...)
		local args = {...}
		local admissible = self:get_methods(...)
		return select_most_specialized(args, admissible)
	end

	local mt = {}
	function mt:__newindex(key, value)
		self.methods[key] = value
	end

	function mt:__call(...)
		local args = terralib.newlist{...}
		local methods = self:select_method(unpack(args))
		local n_methods = fun.length(methods)
		if n_methods == 1 then
			local sig, func = next(methods)
			return sig, (func or self.default)(...)
		elseif n_methods > 1 then
			--throw an ambiguity error
			local err_str = ""
			-- terralist has a nice tostring method
			local arg = terralib.newlist({...})
			err_str = err_str
				.. string.format("For signature %s there's\n", tostring(arg))
			for sig, func in pairs(methods) do
				err_str = err_str
					.. tostring(sig) .. "\n"
			end
        	return error("The following method calls are ambiguous:\n" .. err_str, 2)
		end
	end

	function template:adddefinition(methods)
		methods = methods or {}
		for sig,func in pairs(methods) do
			--check if method with this serialized key already exists
			for s,v in pairs(self.methods) do
				if sig:serialize()==s:serialize() then --overwrite old definition
					self[s] = func
					return
				end
			end
			self[sig] = func
        end
    end

	return setmetatable(template, mt)
end

local function istemplate(T)
	return type(T) == "table" and T.type == "template"
end

local function isfunctiontemplate(T)
	if not (T.templates and T.templates.eval) then
		return false
	end
	return istemplate(T.templates.eval)
end

local function isvarargtemplatefun(sig, func)
	return sig.keys[#sig.keys] == concept.Vararg
end

local function dispatch(T, ...)
    return T.templates.eval(...)
end

local functiontemplate = function(name, methods)
    local T = terralib.types.newstruct(name)
    base.AbstractBase(T) --adding table 'staticmethods', 'templates'
	T.templates.eval = Template:new("eval")
	T.metamethods.__apply = macro(function(self, ...)
        local args = terralib.newlist{...}
        local types = args:map(function(a) return a:gettype() end)
        local sig, func = dispatch(T, unpack(types))
		if func then
			if not sig:isvararg() then
        		return `func([args])
			else
				local newargs, varargs = terralib.newlist(), terralib.newlist()
				local m = sig:len()-1 --sig includes concept Vararg. Therefore we subtract 1.
				for k = 1, m do
					newargs:insert(args[k])
				end 
				for k = m+1,#args do
					varargs:insert(args[k])
				end 
				return `func([newargs],{[varargs]})
			end
		end
		error("No implemementation found that satisfies the concept check.", 2)
    end)

    local t = constant(T)
    function t:adddefinition(methods)
		methods = methods or {}
        for sig, func in pairs(methods) do
			--check if method with this serialized key already exists
			for s,v in pairs(T.templates.eval.methods) do
				if sig:serialize()==s:serialize() then --overwrite old definition
					T.templates.eval[s] = func
					return
				end
			end
			--otherwise add new definition with new key
			T.templates.eval[sig] = func
        end
    end
    function t:dispatch(...)
		local sig, func = dispatch(T, ...)
        return func
    end

	t:adddefinition(methods)

    return t
end

return {
	paramlist = paramlist,
	Template = Template,
	functiontemplate = functiontemplate,
	istemplate = istemplate,
	isfunctiontemplate = isfunctiontemplate
}

