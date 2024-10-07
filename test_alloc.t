-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local io = terralib.includec("stdio.h")
import "terratest/terratest"

local alloc = require("alloc")
local DefaultAllocator = alloc.DefaultAllocator()

testenv "Block - Default allocator" do

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
        test y:size() == 2
        test y:owns_resource()
		test y:get(0) == 1.0
		test y:get(1) == 2.0
	end

	testset "__init - generated" do
		terracode
			var x : alloc.block
		end
		test x.ptr == nil
		test x.nbytes == 0
		test x.alloc.data == nil
        test x.alloc.tab == nil
		test x:size() == 0
		test x:isempty()
	end

	testset "__copy - constructor - generated" do
		terracode
			var x = A:allocate(sizeof(double), 2)
			var y = x
		end
		test y.ptr == x.ptr
		test y.alloc.data == nil
        test y.alloc.tab == nil
		test y:size_in_bytes() == 16
		test x:owns_resource() and y:borrows_resource()
	end

	testset "__dtor - explicit" do
		terracode
			var x = A:allocate(sizeof(double), 2)
			x:__dtor()
		end
		test x.ptr == nil
		test x.alloc.data == nil
		test x.alloc.tab == nil
		test x:size() == 0
		test x:isempty()
	end

	testset "__dtor - explicit - borrowed resource" do
		terracode
			var x = A:allocate(sizeof(double), 2)
			var y = x --y is a view of the data
			y:__dtor()
		end
		test x:size_in_bytes() == 16
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
		test x:size_in_bytes() == 16
		test A:owns(&x)
	end

	testset "allocator - free" do
		terracode
			var x = A:allocate(sizeof(double), 2)
			A:deallocate(&x)
		end
		test x.ptr == nil
		test x.alloc.data == nil
		test x.alloc.tab == nil
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
            io.printf("size y: %d\n", y:size())
		end
		test y:size() == 5
		for i=0,2 do
			test y:get(i)==i
		end
	end

end

testenv "singly linked list - that is a cycle" do

	local Allocator = alloc.Allocator

    --implementation of singly-linked list
    local struct s_node
    local smrt_s_node = alloc.SmartBlock(s_node)

    --metamethod used here for testing - counting the number
    --of times the __dtor method is called
    local smrt_s_node_dtor_counter = global(int, 0)
    smrt_s_node.metamethods.__dtor = macro(function(self)
        return quote
            if self:owns_resource() then
                smrt_s_node_dtor_counter  = smrt_s_node_dtor_counter + 1
            end
        end
    end)

    smrt_s_node.metamethods.__entrymissing = macro(function(entryname, self)
        return `self.ptr.[entryname]
    end)

    smrt_s_node.metamethods.__methodmissing = macro(function(method, self, ...)
        local args = terralib.newlist{...}
        return `self.ptr:[method](args)
    end)

    struct s_node{
        index : int
        next : smrt_s_node
    }
    s_node:complete()

    smrt_s_node.metamethods.__eq = terra(self : &smrt_s_node, other : &smrt_s_node)
        if not self:isempty() and not other:isempty() then
            return self.ptr == other.ptr
        end
        return false
    end

    terra smrt_s_node:allocate_next(A : Allocator)
        self.next = A:allocate(sizeof(s_node), 1)
        self.next.index = self.index + 1
    end

    terra smrt_s_node:set_next(next : &smrt_s_node)
        self.next = next  --create a view
    end

    terracode
        var A : DefaultAllocator
    end

    testset "next" do
        terracode
            --define head node
            var head : smrt_s_node = A:allocate(sizeof(s_node), 1)
            head.index = 0
            --make allocations
            head:allocate_next(&A)  --node 1
            head.next:allocate_next(&A) --node 2
            head.next.next:allocate_next(&A) --node 3
            --close loop
            head.next.next.next:set_next(&head) --node 3
            --get pointers to nodes
            var node_0 = head
            var node_1 = node_0.next
            var node_2 = node_1.next
            var node_3 = node_2.next
        end
        --next node
        test node_0.next==node_1
        test node_1.next==node_2
        test node_2.next==node_3
        test node_3.next==node_0
    end

    testset "__dtor - head on the stack" do
        terracode
            smrt_s_node_dtor_counter = 0
            do
                --define head node
                var head : smrt_s_node = A:allocate(sizeof(s_node), 1)
                head.index = 0
                --make allocations
                head:allocate_next(&A)  --node 1
                head.next:allocate_next(&A) --node 2
                head.next.next:allocate_next(&A) --node 3
                --close loop
                head.next.next.next:set_next(&head) --node 3
            end
        end
        test smrt_s_node_dtor_counter==4
    end
end


testenv "doubly linked list - that is a cycle" do

	local Allocator = alloc.Allocator

    --implementation of double-linked list
    local struct d_node
    local smrt_d_node = alloc.SmartBlock(d_node)

    --metamethod used here for testing - counting the number
    --of times the __dtor method is called
    local smrt_d_node_dtor_counter = global(int, 0)
    smrt_d_node.metamethods.__dtor = macro(function(self)
        return quote
            if self:owns_resource() then
                smrt_d_node_dtor_counter  = smrt_d_node_dtor_counter + 1
            end
        end
    end)

    smrt_d_node.metamethods.__entrymissing = macro(function(entryname, self)
        return `self.ptr.[entryname]
    end)

    smrt_d_node.metamethods.__methodmissing = macro(function(method, self, ...)
        local args = terralib.newlist{...}
        return `self.ptr:[method](args)
    end)

    struct d_node{
        index : int
        prev : smrt_d_node
        next : smrt_d_node
    }
    d_node:complete()


    smrt_d_node.metamethods.__eq = terra(self : &smrt_d_node, other : &smrt_d_node)
        if not self:isempty() and not other:isempty() then
            return self.ptr == other.ptr
        end
        return false
    end

    terra smrt_d_node:allocate_next(A : Allocator)
        self.next = A:allocate(sizeof(d_node), 1)
        self.next.index = self.index + 1
        self.next.prev = self --create a view
    end

    terra smrt_d_node:set_next(next : &smrt_d_node)
        self.next = next  --create a view
    end

    terra smrt_d_node:set_prev(prev : &smrt_d_node)
        self.prev = prev  --create a view
    end

    terracode
        var A : DefaultAllocator
    end

    testset "next and prev" do
        terracode
            --define head node
            var head : smrt_d_node = A:allocate(sizeof(d_node), 1)
            head.index = 0
            --make allocations
            head:allocate_next(&A)  --node 1
            head.next:allocate_next(&A) --node 2
            head.next.next:allocate_next(&A) --node 3
            --close loop
            head:set_prev(&head.next.next.next)
            head.next.next.next:set_next(&head) --node 3
            --get pointers to nodes
            var node_0 = head
            var node_1 = node_0.next
            var node_2 = node_1.next
            var node_3 = node_2.next
        end
        --next node
        test node_0.next==node_1
        test node_1.next==node_2
        test node_2.next==node_3
        test node_3.next==node_0
        --previous node
        test node_0.prev==node_3
        test node_1.prev==node_0
        test node_2.prev==node_1
        test node_3.prev==node_2
    end

    testset "__dtor" do
        terracode
            smrt_d_node_dtor_counter = 0
            do
                --define head node
                var head : smrt_d_node = A:allocate(sizeof(d_node), 1)
                head.index = 0
                --make allocations
                head:allocate_next(&A)  --node 1
                head.next:allocate_next(&A) --node 2
                head.next.next:allocate_next(&A) --node 3
                --close loop
                head:set_prev(&head.next.next.next)
                head.next.next.next:set_next(&head) --node 3
            end
        end
        test smrt_d_node_dtor_counter==4
    end
end