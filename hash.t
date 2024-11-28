-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"

local err = require("assert")
local template = require("template")
local concept = require("concept")
local string = terralib.includec("string.h")


local C = terralib.includec("./hashmap/hashmap.h")
local uname = io.popen("uname", "r"):read("*a")
if uname == "Darwin\n" then
    terralib.linklibrary("./libhash.dylib")
elseif uname == "Linux\n" then
    terralib.linklibrary("./libhash.so")
else
    error("Not implemented for this OS.")
end

local M = {}

terraform primitive_compare(a: &T, b: &T) where {T: concept.Primitive}
	if @a > @b then
		return 1
	elseif @a < @b then
		return -1
	else
		return 0
	end
end

terraform primitive_compare(a: &&opaque, b: &&opaque)
	var ae = [int64](@a)
	var be = [int64](@b)
	escape
		local impl = primitive_compare:dispatch(&int64, &int64)
		emit quote return impl(&ae, &be) end
	end
end

terraform primitive_compare(a: &rawstring, b: &rawstring)
	return string.strcmp(@a, @b)
end

terraform primitive_length(a: &T) where {T: concept.Primitive}
	var size: int64 = [sizeof(a.type.type)]
	return size
end

terraform primitive_length(a: &&opaque)
	return 8l -- 64 bit platform
end

terraform primitive_length(a: &rawstring)
	var size: int64 = string.strlen(@a)
	return size
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
	length = length or primitive_length:dispatch(&I)
	assert(length, "Need to pass custom length function")
	local ref_length = &I -> int64
	assert(length.type == ref_length.type,
		"Custom length has wrong type")

	compare = compare or primitive_compare:dispatch(&I, &I)
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
