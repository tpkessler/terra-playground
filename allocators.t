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
    }

    local Allocator = interface.Interface:new{
        allocate = {size_t} -> {block},
        deallocate = {block} -> {}
    }

    block.staticmethods = {}

    block.methods.__init = terra(self : &block)
        self.ptr = nil
        self.size = 0
        self.allocator = nil
    end

    block.methods.get = macro(function(self, i)
        return `self.ptr[i]
    end)

    block.methods.set = macro(function(self, i, v)
        return quote 
            self.ptr[i] = v
        end
    end)

    block.methods.size = macro(function(self)
        return `self.size
    end)

    local struct default{
    }

    terra default:allocate(size : size_t)
        var alignment = 64 -- Memory alignment for AVX512    
        var ptr : &opaque = nil 
        var res = C.posix_memalign(&ptr, alignment, size * sizeof(T))
        return block{[&T](ptr), size, [&opaque](self)}
    end

    terra default:deallocate(mem : block)
        C.printf("deallocating\n")
        C.free(mem.ptr)
    end

    Allocator:isimplemented(default)

    return {
        memblock = block, 
        Allocator = Allocator,
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
    --x:deallocate(blk)
    a:deallocate(blk)
end

main()

