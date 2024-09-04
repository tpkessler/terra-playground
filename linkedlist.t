local io = terralib.includec("stdio.h")

local alloc = require("alloc")

local DefaultAllocator =  alloc.DefaultAllocator()
local Allocator = alloc.Allocator

local size_t = uint64

local struct snode
local smrt_snode = alloc.SmartBlock(snode)

struct snode{
    index : int
    next : smrt_snode
}
snode:complete()

local struct dnode
local smrt_dnode = alloc.SmartBlock(dnode)

struct dnode{
    index : int
    prev : smrt_dnode
    next : smrt_dnode
}
dnode:complete()


import "terratest/terratest"

testenv "singly linked list - that is a cycle" do

    terracode
        var A : DefaultAllocator 
    end

    testset "next" do
        terracode 
            --head dsode
            var node_0 : snode
            node_0.next = A:allocate(sizeof(snode), 1)
            --node 1
            var node_1 = node_0.next.ptr
            node_1.next = A:allocate(sizeof(snode), 1)
            --node 2
            var node_2 = node_1.next.ptr
            node_2.next = A:allocate(sizeof(snode), 1)
            --node 3
            var node_3 = node_2.next.ptr
            node_3.next.ptr = &node_0 --close the loop
        end
        test node_0.next.ptr==node_1
        test node_1.next.ptr==node_2
        test node_2.next.ptr==node_3
        test node_3.next.ptr==&node_0
    end

end


testenv "doubly linked list" do

    terracode
        var A : DefaultAllocator     
        --head dnode
        var node_0 : dnode
        node_0.next = A:allocate(sizeof(dnode), 1)
        --dnode 1
        var node_1 = node_0.next.ptr
        node_1.prev.ptr = &node_0
        node_1.next = A:allocate(sizeof(dnode), 1)
        --dnode 2
        var node_2 = node_1.next.ptr
        node_2.prev.ptr = node_1
        node_2.next = A:allocate(sizeof(dnode), 1)
        --dnode 3
        var node_3 = node_2.next.ptr
        node_3.prev.ptr = node_2
        node_3.next.ptr = &node_0
        --close the loop
        node_0.prev.ptr = node_3
    end

    testset "next" do
         test node_0.next.ptr==node_1
         test node_1.next.ptr==node_2
         test node_2.next.ptr==node_3
         test node_3.next.ptr==&node_0
    end

    testset "prev" do
         test node_0.prev.ptr==node_3
         test node_3.prev.ptr==node_2
         test node_2.prev.ptr==node_1
         test node_1.prev.ptr==&node_0
    end

end