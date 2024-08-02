local concept = require("concept")
local fun = require("fun")

local Template = {}

local function sgn(x)
	return x > 0 and 1 or x < 0 and -1 or 0
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
		if #sig~= #args then
			return false
		end
		local res = fun.all(function(C, T) return C(T) end, fun.zip(sig, args))
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
			elseif concept.is_specialized_over(c_1, c_2) then
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
							  return concepts_check(sig.parameters, args)
						  end,
						  self.methods
						 )
						 -- For later comparison we only return the function
						 -- parameters but not its return type.
						 :map(function(sig, func) return sig.parameters, func end)
						 :tomap()
	end

	function template:select_method(...)
		local args = {...}
		local admissible = self:get_methods(...)
	
		-- Matches every concept
		local Any = concept.Any
		local saved = terralib.newlist()
		for i = 1, #args do
			saved:insert(Any)
		end
		local function minimal(acc, sig, func)
			local s = compare_two_methods(sig, acc)
			if s > 0 then -- sig is more specialized
				return sig
			else
				return acc
			end
		end
		-- Find minimal, most specialized implementation
		saved = fun.foldl(minimal, saved, admissible)

		local function ambiguous(sig, func)
			local s = compare_two_methods(sig, saved)
			if s == 0 then
				return true
			else
				return false
			end
		end
		local methods = fun.filter(ambiguous, admissible):tomap()

		return methods
	end

	local mt = {}
	function mt:__newindex(key, value)
		assert(terralib.types.istype(key) and key:ispointertofunction(),
			"Need to pass function pointer but got " .. tostring(key))
		key = key.type
		self.methods[key] = value
	end

	function mt:__call(...)
		local methods = self:select_method(...) 
		local len = fun.length(methods)
		if len > 1 then
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
		else
			local sig, func = next(methods)
			return (func or self.default)(...)
		end
	end

	return setmetatable(template, mt)
end

local function istemplate(T)
	return type(T) == "table" and T.type == "template"
end

return {
	Template = Template,
	istemplate = istemplate,
}

