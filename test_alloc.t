import "terratest/terratest"

local io = terralib.includec("stdio.h")

local Alloc = require("alloc")

terra main()
    var x : Alloc.default
	var empty_block : Alloc.block
	io.printf("address of heap: %p\n", empty_block.ptr)
	var blk = x:allocate(8, 10)
    io.printf("size of allocation: %d\n", blk:size())
	io.printf("address of heap: %p\n", blk.ptr)
	blk:__dtor()
	io.printf("checking block.ptr is nil: %p\n", blk.ptr)
end

main()


testenv "Default allocator" do
	terracode
		var A : Alloc.default
		var x : Alloc.block
	end

	testset "Init" do
		test x.ptr == nil
		test x:size() == 0
	end

	testset "Alloc" do
		terracode
			x = A:allocate(sizeof(double), 2)
		end
		test x.ptr ~= nil
		test A:owns(&x)
	end


	testset "Free - using allocator" do
		terracode
			x = A:allocate(sizeof(double), 2)
			A:deallocate(&x)
		end
		test x.ptr == nil
		test x.size == 0
		test x.dealloc.handle == nil
		test x.dealloc.deallocate == nil
	end

	testset "Free - using __dtor" do
		terracode
			x = A:allocate(sizeof(double), 2)
			x:__dtor()
		end
		test x.ptr == nil
		test x.size == 0
		test x.dealloc.handle == nil
		test x.dealloc.deallocate == nil
	end

end

