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


local function Allocators(T)

    --opaque allocator object with only the 'deallocate' 
    --method available
    local struct deallocator{
        handle : &opaque        --handle to the allocator instance
        deallocate : {&opaque, block} -> {}    --pointer to its 'deallocate' method
    }

    local struct block{
        ptr : &T
        size : size_t
        dealloc : deallocator
    }

    block.staticmethods = {}

    block.methods.__init = terra(self : &block)
        self.ptr = nil
        self.size = 0
    end

    block.methods.get = terra(self : &block, i : size_t)
        return self.ptr[i]
    end

    block.methods.set = terra(self : &block, i : size_t, v : T)
        self.ptr[i] = v
    end

    block.methods.size = terra(self : &block)
        return self.size
    end

    block.methods.get:setinlined(true)
    block.methods.set:setinlined(true)
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

    terra default:allocate(size : size_t)
        var alignment = 64 -- Memory alignment for AVX512    
        var ptr : &opaque = nil 
        var res = C.posix_memalign(&ptr, alignment, size * sizeof(T))
        var deallocator = deallocator{[&opaque](self), [{&opaque, block} -> {}](fptr)}
        return block{[&T](ptr), size, deallocator}
    end

    --Allocator:isimplemented(default)

    return {
        memblock = block, 
        Default = default
    }
end


local Alloc = Allocators(double) 

terra main()
    var x : Alloc.Default
    var blk = x:allocate(10)
    C.printf("address x : %p\n", &x)
    C.printf("size of allocation: %d\n", blk:size())
end

main()

