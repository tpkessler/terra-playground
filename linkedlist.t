local alloc = require("alloc")

local DefaultAllocator =  alloc.DefaultAllocator()
local Allocator = alloc.Allocator

local struct node
local smrtnode = alloc.SmartBlock(node)

struct node{
    prev : smrtnode
    next : smrtnode
}
node:complete()

terra main()
    var A : DefaultAllocator
    --head node
    var mynode : node
    mynode.next = A:allocate(sizeof(node), 1)
    mynode.prev = A:allocate(sizeof(node), 1)
    --next node
    mynode.next.ptr.next = mynode.prev
    mynode.next.ptr.prev.ptr = &mynode
    --prev node
    mynode.prev.ptr.prev = mynode.next
    mynode.prev.ptr.next.ptr = &mynode
end
main()