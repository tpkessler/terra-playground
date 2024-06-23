local hash = require("hash")
local string = terralib.includec("string.h")

local terra length_str(a: &rawstring)
	var size: int64 = string.strlen(@a)
	return size
end

local terra compare_str(a: &rawstring, b: &rawstring)
	return string.strcmp(@a, @b)
end

local HashMap = hash.HashMap(rawstring, int32, length_str, compare_str)

import "terratest/terratest"

testenv "HashMap with strings" do
	terracode
		var map = HashMap.new()
		defer map:free()
	end

	testset "Setters and Getters" do
		terracode
			var key = "Alice"
			var val = 43
			map:set(key, val)
			var val_map = map:get(key)
			var len = map:size()
		end
		test val == val_map
		test len == 1
	end
end

local terra length_ptr(a: &&opaque)
	return 8l
end

local terra compare_ptr(a: &&opaque, b: &&opaque)
	var addr_a = [int64](@a)
	var addr_b = [int64](@b)

	if addr_a > addr_b then
		return 1
	elseif addr_a < addr_b then
		return -1
	else
		return 0
	end
end

local HashPtr = hash.HashMap(&opaque, int64, length_ptr, compare_ptr)

testenv "HashMap with pointers" do
	terracode
		var map = HashPtr.new()
		defer map:free()
		var x: double[4]
		var y: int[31]
		map:set(&x, 4 * 8)
		map:set(&y, 31 * 4)
		var len = map:size()
	end

	testset "Size" do
		test len == 2
	end

	testset "Getters" do
		terracode
			var bytes_double = map:get(&x)
			var bytes_int = map:get(&y)
		end
		test bytes_double == 4 * 8
		test bytes_int == 31 * 4
	end
end
