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

    local struct block{
        ptr : &T
        size : size_t
        allocator : &opaque
        deallocator : &opaque
    }

    terra block:deallocate()
        C.printf("Calling block.methods.deallocate. \n")
        var f = [{&opaque, block} -> {}](self.deallocator)
        f(self.allocator, @self)
	end

    block.staticmethods = {}

    block.methods.__init = terra(self : &block)
        self.ptr = nil
        self.size = 0
        self.allocator = nil
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

    local struct default{
    }

    terra default:deallocate(mem : block)
        C.printf("deallocating\n")
        C.free(mem.ptr)
    end

    local fptr = constant(default.methods.deallocate:getpointer())

    terra default:allocate(size : size_t)
        var alignment = 64 -- Memory alignment for AVX512    
        var ptr : &opaque = nil 
        var res = C.posix_memalign(&ptr, alignment, size * sizeof(T))
        return block{[&T](ptr), size, [&opaque](self), [&opaque](fptr)}
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
    var a = @[&Alloc.Default](blk.allocator)
    C.printf("address x : %p\n", &x)
    C.printf("address a : %p\n", &a)
    C.printf("size of allocation: %d\n", blk:size())
    blk:deallocate()
end

main()

