-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

local io = terralib.includec("stdio.h")
local alloc = require("alloc")

local DefaultAllocator = alloc.DefaultAllocator()
local doubles = alloc.SmartBlock(double)

--metamethod used here for testing - counting the number
--of times the __dtor method is called
local __dtor_counter = global(int, 0)
doubles.metamethods.__dtor = macro(function(self)
    return quote
        if self:owns_resource() then
            __dtor_counter = __dtor_counter + 1
        end
    end
end)


testenv "Block - Default allocator" do
	terracode
		var A : DefaultAllocator
	end

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

	testset "__copy - constructor - generated" do
		terracode
			var x = A:allocate(sizeof(double), 2)
			var y = x
		end
		test y.ptr == x.ptr
		test y.alloc_h == x.alloc_h
		test y.alloc_f == nil
		test y:bytes() == 16
		test x:owns_resource() and y:borrows_resource()
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

	testset "__dtor - explicit - borrowed resource" do
		terracode
			var x = A:allocate(sizeof(double), 2)
			var y = x --y is a view of the data
			y:__dtor()
		end
		test x:bytes() == 16
		test x:owns_resource() and y:isempty()
	end

	testset "__dtor - generated - owned resource" do
		terracode
			do
				__dtor_counter = 0
				var y : doubles = A:allocate(sizeof(double), 2)
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

	testset "allocator - reallocate" do
		terracode
			var y : doubles = A:allocate(sizeof(double), 3)
			for i=0,3 do
				y:set(i, i)
			end
			A:reallocate(&y, sizeof(double), 5)
		end
		test y:size() == 5
		for i=0,2 do
			test y:get(i)==i
		end
	end

end