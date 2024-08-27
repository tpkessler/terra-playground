local alloc = require("alloc")

local DefaultAllocator =  alloc.DefaultAllocator()
local Allocator = alloc.Allocator


terra main :: {} -> {}

local struct node
local smrtnode = alloc.SmartBlock(node)

struct node{
    next : smrtnode
}
node:complete()


terra main()
    var A : DefaultAllocator
    var mynode : node
    mynode.next = A:allocate(sizeof(node), 1)
    var x = mynode.next:get(0)
end
main()