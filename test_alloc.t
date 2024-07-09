import "terratest/terratest"

local io = terralib.includec("stdio.h")
local Alloc = require("alloc")

local DefaultAllocator = Alloc.DefaultAllocator()
local doubles = Alloc.SmartBlock(double)


terra main()
    var A : DefaultAllocator
	var blk : doubles = A:allocate(sizeof(double), 10)
    io.printf("block size: %d\n", blk:bytes())
    A:reallocate(&blk, sizeof(double), 120)
    io.printf("block size: %d\n", blk:bytes())
end

main()

terra main2()
    var A : DefaultAllocator
	var empty_block : Alloc.block
	io.printf("address of heap: %p\n", empty_block.ptr)
	var blk = A:allocate(8, 10)
    io.printf("size of allocation: %d\n", blk:size())
	io.printf("address of heap: %p\n", blk.ptr)
	blk:__dtor()
	io.printf("checking block.ptr is nil: %p\n", blk.ptr)
end

main2()

local doubles = Alloc.SmartBlock(double)

terra mytest()
	var A : DefaultAllocator
    var y : doubles = A:allocate(8, 3)
	y:set(0, 3.0)
	io.printf("value of y.ptr: %f\n", @y.ptr)
	io.printf("value of y.size: %d\n", y:size())
end

mytest()

local DefaultAllocator = Alloc.DefaultAllocator()

testenv "Default allocator" do
	terracode
		var A : DefaultAllocator
		var x : Alloc.block
	end

	testset "Init" do
		test x.ptr == nil
		test x:size() == 0
        test x.alloc == nil
	end

	testset "Alloc" do
		terracode
			x = A:allocate(sizeof(double), 2)
		end
		test x:isempty() == false
		test A:owns(&x)
	end

	testset "Free - using allocator" do
		terracode
			x = A:allocate(sizeof(double), 2)
			A:deallocate(&x)
		end
		test x:isempty()
	end

	testset "Free - using __dtor" do
		terracode
			x = A:allocate(sizeof(double), 2)
			x:__dtor()
		end
		test x:isempty()
	end

	local doubles = Alloc.SmartBlock(double)

	testset "Cast opaque block to typed block" do
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
