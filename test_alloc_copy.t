-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

local io = terralib.includec("stdio.h")
local alloc = require("alloc")

local DefaultAllocator = alloc.DefaultAllocator()
local doubles = alloc.SmartBlock(double)

doubles.metamethods.__dtor = macro(function(self)
    return quote
        if self:owns_resource() then
            io.printf("calling __dtor\n")
        end
    end
end)

terra main()
    var A : DefaultAllocator
	var y : doubles = A:allocate(sizeof(double), 10)
    io.printf("block size: %d\n", y:bytes())
	for i=0,10 do
		y:set(i, i)
	end
	for i=0,10 do
		io.printf("v(i) = %0.2f\n", y:get(i))
	end
    A:reallocate(&y, sizeof(double), 120)
    io.printf("block size: %d\n", y:bytes())
end
main()

terra main2()
    var A : DefaultAllocator
	var empty_block : alloc.block
	io.printf("address of heap: %p\n", empty_block.ptr)
	var blk = A:allocate(8, 10)
    io.printf("size of allocation: %d\n", blk:size())
	io.printf("address of heap: %p\n", blk.ptr)
	blk:__dtor()
	io.printf("checking block.ptr is nil: %p\n", blk.ptr)
end
main2()

local doubles = alloc.SmartBlock(double)

terra mytest()
	var A : DefaultAllocator
    var y : doubles = A:allocate(8, 3)
	y:set(0, 3.0)
	io.printf("value of y.ptr: %f\n", @y.ptr)
	io.printf("value of y.size: %d\n", y:size())
end

mytest()

local DefaultAllocator = alloc.DefaultAllocator()
--metamethod used here for testing - counting the number
--of times the __dtor method is called
local __dtor_counter = global(int, 0)
alloc.block.metamethods.__dtor = macro(function(self)
    return quote
        if self:owns_resource() then
			io.printf("calling metamethod __dtor\n")
            __dtor_counter  = __dtor_counter + 1
        end
    end
end)

testenv "Block - Default allocator" do
	terracode
		var A : DefaultAllocator
	end

	testset "__init - generated" do
		terracode
			var x : alloc.block
		end
		test x.ptr == nil
		test x.alloc_h == nil
		test x.alloc_f == nil
		test x:size() == 0
		test x:isempty()
	end

	testset "__dtor - explicit" do
		terracode
			var x = A:allocate(sizeof(double), 2)
			x:__dtor()
		end
		test x.ptr == nil
		test x.alloc_h == nil
		test x.alloc_f == nil
		test x:size() == 0
		test x:isempty()
	end

	testset "__dtor - generated" do
		terracode
			do
				__dtor_counter = 0
				var y = A:allocate(sizeof(double), 2)
			end
		end
		test __dtor_counter==1
	end

	testset "allocator - owns" do
		terracode
			var x = A:allocate(sizeof(double), 2)
		end
		test x:isempty() == false
		test x:bytes() == 16
		test A:owns(&x)
	end

	testset "allocator - free" do
		terracode
			var x = A:allocate(sizeof(double), 2)
			A:deallocate(&x)
		end
		test x.ptr == nil
		test x.alloc_h == nil
		test x.alloc_f == nil
		test x:size() == 0
		test x:isempty()
	end

	local doubles = alloc.SmartBlock(double)

	testset "cast opaque block to typed block" do
		terracode
			var y : doubles = A:allocate(sizeof(double), 2)
			y:set(0, 1.0)
			y:set(1, 2.0)
		end
        test y:isempty() == false
		test y:get(0) == 1.0
		test y:get(1) == 2.0
		test y:size() == 2
	end

end