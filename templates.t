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
	}

    -- Check if method signature satisfies method concepts.
    -- This is used to rule out methods, such that only admissable methods remain.
    local function concepts_check(concepts, args)
		if #concepts ~= #args then
			return false
		end
		return fun.all(function(C, T) return C(T) end, fun.zip(concepts, args))
	end

	-- Given two lists of concepts this function returns
	-- -1 if the second argument is more specialized,
	-- +1 if the first  argument is more specialized,
	--  0 if the signatures are ambiguous.
	local function compare_two_methods(clist_1, clist_2)
		assert(#clist_1 == #clist_2,
			   "Can only compare function signatures of equal size")
		local function compare(s, c_1, c_2)
			if c_1:subtypeof(c_2) then
				s[1] = s[1] + 1
			elseif c_1:supertypeof(c_2) then
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
		return fun.filter(function(Carg, func) return concepts_check(Carg, args) end,
						  self.methods
						 ):tomap()
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
		if terralib.types.istype(key) then
			self.methods[{key}] = value
		else
			self.methods[key] = value
		end
	end

	function mt:__call(...)
		local methods = self:select_method(...) 
		local len = fun.length(methods)
		if len > 1 then
			io.stderr:write("Warning: The following method calls are ambiguous", "\n")
			-- terralist has a nice tostring method
			local arg = terralib.newlist({...})
			io.stderr:write("For signature ", tostring(arg), " there's", "\n")
			for sig, func in pairs(methods) do
				io.stderr:write(tostring(terralib.newlist(sig)), "\n")
			end
        	return error("Method call is ambiguous.", 2)
		else
			local sig, func = next(methods)
			return (func or self.default)(...)
		end
	end

	return setmetatable(template, mt)
end

-- lua function to create a concept.
-- A concept defines defines a compile-time predicate that defines an equivalence
-- relation on a set.
local Concept = concept.Concept

--primitive number concepts
local Float32 = concept.Float32
local Float64 = concept.Float64
local Int8    = concept.Int8
local Int16   = concept.Int16
local Int32   = concept.Int32
local Int64   = concept.Int64

-- abstract floating point numbers
local Float = concept.Float

--abstract integers
local Integer = concept.Integer

--test foo template implementation
local foo = Template:new()

foo[Integer] = function(T)
    print("Method for {Integer}")
end

foo[Float] = function(T)
    print("Method for {Float}")
end

foo[{Integer,Integer}] = function(T1, T2)
    print("Method for {Integer,Integer}")
end

foo[{Integer,Int32}] = function(T1, T2)
    print("Method for {Integer,Int32}")
end

foo[{Int32,Integer}] = function(T1, T2)
    print("Method for {Int32,Integer}")
end

foo[{Int32,Integer,Float}] = function(T1, T2, T3)
    print("Method for {Int32,Integer,Float}")
end

foo[{Int32,Int32,Float}] = function(T1, T2, T3)
    print("Method for {Int32,Int32,Float}")
end

foo[{Int32,Int32,Float64}] = function(T1, T2, T3)
    print("Method for {Int32,Int32,Float64}")
end

foo(double)
foo(float)
foo(int32)
foo(int64, int64)
foo(int32, int32, double)


-- Uncomment to see the following fail due to the presence of
-- two ambiguous methods
--foo(int32, int32)

--removing the ambiguity by defining the specialization
-- foo[{Int32,Int32}] = function(T1, T2)
-- 	print("Method for {Int32,Int32}")
-- end

-- Try again
-- foo(int32, int32)
