--load 'terralibext' to enable raii
require "terralibext"
local base = require("base")
local template = require("template")
local concept = require("concept")
local interface = require("interface")

local C = terralib.includecstring[[
	#include <stdio.h>
	#include <stdlib.h>
]]

local size_t = uint64

--opaque allocator object with only the 'deallocate' 
--method available
local struct deallocator{
    handle : &opaque        --handle to the allocator instance
    deallocate : {&opaque, block} -> {}    --pointer to its 'deallocate' method
}

local struct block{
    ptr : &opaque
    size : size_t
    dealloc : deallocator
}

block.staticmethods = {}

block.methods.__init = terra(self : &block)
    self.ptr = nil
    self.size = 0
end

block.methods.size = terra(self : &block)
    return self.size
end
block.methods.size:setinlined(true)

block.methods.__dtor = terra(self : &block)
    C.printf("Calling block.methods.deallocate. \n")
    self.dealloc.deallocate(self.dealloc.handle, @self)
end


local struct default{
}

terra default:deallocate(mem : block)
    C.printf("deallocating\n")
    C.free(mem.ptr)
end

--function pointer to the 'deallocate' method of the 'default' allocator
local fptr = constant(default.methods.deallocate:getpointer())

terra default:allocate(size : size_t, count : size_t)
    var alignment = 64 -- Memory alignment for AVX512    
    var ptr : &opaque = nil 
    var res = C.posix_memalign(&ptr, alignment, size * count)
    var deallocator = deallocator{[&opaque](self), [{&opaque, block} -> {}](fptr)}
    return block{ptr, size * count, deallocator}
end


terra main()
    var x : default
    var blk = x:allocate(8, 10)
    C.printf("size of allocation: %d\n", blk:size())
end

main()

