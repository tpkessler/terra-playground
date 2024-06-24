local hash = require("hash")
local string = terralib.includec("string.h")

local HashMap = hash.HashMap(rawstring, int32)

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

local HashPtr = hash.HashMap(&opaque, int64)

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

local HashInt = hash.HashMap(int64, double)

testenv "HashMap with integer indices" do
	terracode
		var map = HashInt.new()
		map:set(10, -123.0)
		map:set(-2, 3.14)
		map:set(0, 2.71)
		var len = map:size()
	end

	testset "Size" do
		test len == 3
	end

	testset "Getters" do
		terracode
			var x = arrayof(double, map:get(0), map:get(10), map:get(-2))
			var xref = arrayof(double, 2.71, -123.0, 3.14)
		end
		for i = 1, 3 do
			test x[i - 1] == xref[i - 1]
		end
	end
end

