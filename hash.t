local C = terralib.includec("hashmap.h")
local stack = require("stack")
local err = require("assert")
terralib.linklibrary("./libhash.so")

local M = {}

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
	local ref_length = &I -> int64
	assert(length.type == ref_length.type)

	local ref_compare = {&I, &I} -> int32
	assert(compare.type == ref_compare.type)

	local entry, hash = unpack(get_types(I, T))

	local terra compare_c(a: &opaque, b: &opaque, udata: &opaque)
		var ae = @[&entry](a)
		var be = @[&entry](b)
		return compare(&ae.key, &be.key)
	end

	local terra hash_c(a: &opaque, seed0: uint64, seed1: uint64)
		var ae = @[&entry](a)
		return C.hashmap_sip(ae.key, length(&ae.key), seed0, seed1)
	end

	local terra new()
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

	local S = stack.Stacker(T, I)
	S:isimplemented(hash)

	local static_methods = {
		new = new
	}

	hash.metamethods.__getmethod = function(Self, name)
		return hash.methods[name] or static_methods[name]
	end

	return hash
end

return M
