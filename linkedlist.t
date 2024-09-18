-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local io = terralib.includec("stdio.h")

local alloc = require("alloc")

local DefaultAllocator =  alloc.DefaultAllocator()
local Allocator = alloc.Allocator

local size_t = uint64

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

terra s_node:allocate_next(A : Allocator)
    self.next = A:allocate(sizeof(s_node), 1)
    self.next.index = self.index + 1
end

terra s_node:set_next(next : &s_node)
    self.next.ptr = next
end


import "terratest/terratest"

testenv "doubly linked list - that is a cycle" do

    terracode
        var A : DefaultAllocator
    end

    testset "next" do
        terracode
            --define head node
            var head : s_node
            head.index = 0
            --make allocations
            head:allocate_next(&A)  --node 1
            head.next:allocate_next(&A) --node 2
            head.next.next:allocate_next(&A) --node 3
            --close loop
            head.next.next.next:set_next(&head) --node 3
            --get pointers to nodes
            var node_0 = &head
            var node_1 = node_0.next.ptr
            var node_2 = node_1.next.ptr
            var node_3 = node_2.next.ptr
        end
        --next node
        test node_0.next.ptr==node_1
        test node_1.next.ptr==node_2
        test node_2.next.ptr==node_3
        test node_3.next.ptr==node_0
    end

    testset "__dtor - head on the stack" do
        terracode
            smrt_s_node_dtor_counter = 0
            do
                --define head node
                var head : s_node
                head.index = 0
                --make allocations
                head:allocate_next(&A)  --node 1
                head.next:allocate_next(&A) --node 2
                head.next.next:allocate_next(&A) --node 3
                --close loop
                head.next.next.next:set_next(&head) --node 3
            end
        end
        test smrt_s_node_dtor_counter==3
    end
end


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

terra d_node:allocate_next(A : Allocator)
    self.next = A:allocate(sizeof(d_node), 1)
    self.next.index = self.index + 1
    self.next.prev.ptr = self
end

terra d_node:set_next(next : &d_node)
    self.next.ptr = next
end

terra d_node:set_prev(prev : &d_node)
    self.prev.ptr = prev
end



testenv "doubly linked list - that is a cycle" do

    terracode
        var A : DefaultAllocator
    end

    testset "next and prev" do
        terracode
            --define head node
            var head : d_node
            head.index = 0
            --make allocations
            head:allocate_next(&A)  --node 1
            head.next:allocate_next(&A) --node 2
            head.next.next:allocate_next(&A) --node 3
            --close loop
            head:set_prev(head.next.next.next.ptr)
            head.next.next.next:set_next(&head) --node 3
            --get pointers to nodes
            var node_0 = &head
            var node_1 = node_0.next.ptr
            var node_2 = node_1.next.ptr
            var node_3 = node_2.next.ptr
        end
        --next node
        test node_0.next.ptr==node_1
        test node_1.next.ptr==node_2
        test node_2.next.ptr==node_3
        test node_3.next.ptr==node_0
        --previous node
        test node_0.prev.ptr==node_3
        test node_1.prev.ptr==node_0
        test node_2.prev.ptr==node_1
        test node_3.prev.ptr==node_2
    end

    testset "__dtor - head on the stack" do
        terracode
            smrt_d_node_dtor_counter = 0
            do
                --define head node
                var head : d_node
                head.index = 0
                --make allocations
                head:allocate_next(&A)  --node 1
                head.next:allocate_next(&A) --node 2
                head.next.next:allocate_next(&A) --node 3
                --close loop
                head:set_prev(head.next.next.next.ptr)
                head.next.next.next:set_next(&head) --node 3
            end
        end
        test smrt_d_node_dtor_counter==3
    end
end
