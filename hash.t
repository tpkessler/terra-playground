local C = terralib.includec("hashmap.h")
local err = require("assert")
local template = require("template")
local concept = require("concept")
local string = terralib.includec("string.h")
terralib.linklibrary("./libhash.so")

local M = {}

local primitive_compare = template.Template:new()
primitive_compare[concept.Primitive] = function(T)
	local terra impl(a: &T, b: &T)
		if @a > @b then
			return 1
		elseif @a < @b then
			return -1
		else
			return 0
		end
	end

	return impl
end

primitive_compare[concept.Pointer] = function(T)
	local impl64 = primitive_compare(int64)
	local terra impl(a: &T, b: &T)
		var ae = [int64](@a)
		var be = [int64](@b)
		return impl64(&ae, &be)
	end

	return impl
end

primitive_compare[concept.RawString] = function(T)
	local terra impl(a: &rawstring, b: &rawstring)
		return string.strcmp(@a, @b)
	end

	return impl
end

local primitive_length = template.Template:new()

primitive_length[concept.Primitive] = function(T)
	local terra impl(a: &T)
		var size: int64 = sizeof(T)
		return size
	end
	return impl
end

primitive_length[concept.Pointer] = function(T)
	local terra impl(a: &T)
		return 8l -- 64 bit platform
	end
	return impl
end

primitive_length[concept.RawString] = function(T)
	local terra impl(a: &rawstring)
		var size: int64 = string.strlen(@a)
		return size
	end
	return impl
end

local get_types = terralib.memoize(function(I, T)
	local struct entry{
		key: I
		val: T
	}

	local struct hash{
		data: &C.hashmap
	}

	return {entry, hash}
end)

M.HashMap = function(I, T, length, compare)
	length = length or primitive_length(I)
	assert(length, "Need to pass custom length function")
	local ref_length = &I -> int64
	assert(length.type == ref_length.type,
		"Custom length has wrong type")

	compare = compare or primitive_compare(I)
	assert(compare, "Need to pass custom comparison function")
	local ref_compare = {&I, &I} -> int32
	assert(compare.type == ref_compare.type,
		"Custom comparison has wrong type")

	local entry, hash = unpack(get_types(I, T))

	local terra compare_c(a: &opaque, b: &opaque, udata: &opaque)
		var ae = @[&entry](a)
		var be = @[&entry](b)
		return compare(&ae.key, &be.key)
	end

	local terra hash_c(a: &opaque, seed0: uint64, seed1: uint64)
		var ae = @[&entry](a)
		return C.hashmap_sip(&ae.key, length(&ae.key), seed0, seed1)
	end

	local terra new()
		-- TODO Pass custom allocators
		var data = C.hashmap_new(sizeof(entry), 0, 0, 0, hash_c, compare_c, nil, nil)
		return hash {data}
	end

	terra hash:free()
		C.hashmap_free(self.data)
	end

	terra hash:size()
		var size: int64 = C.hashmap_count(self.data)
		return size
	end

	terra hash:set(key: I, val: T)
		var key_val = entry {key, val}
		C.hashmap_set(self.data, &key_val)
	end

	terra hash:get(key: I)
		var lookup = entry {key}
		var res = C.hashmap_get(self.data, &lookup)
		err.assert(res ~= nil)
		return [&entry](res).val
	end

	local static_methods = {
		new = new
	}

	hash.metamethods.__getmethod = function(Self, name)
		return hash.methods[name] or static_methods[name]
	end

	return hash
end

return M
