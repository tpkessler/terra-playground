--load 'terralibext' to enable raii
require "terralibext"
local base = require("base")
local template = require("template")
local concept = require("concept")
local interface = require("interface")
local alloc = require("alloc")

local C = terralib.includecstring[[
	#include <stdio.h>
	#include <stdlib.h>
]]


local Allocator = interface.Interface:new{
	alloc = uint64 -> {&opaque},
	free = &opaque -> {}
}

local Allocator = alloc.Allocator
local size_t = uint64

local function MemoryBlock(T)

    local struct memblock{
        ptr : &T
        size : size_t
        allocator : &Allocator
    }

    memblock.staticmethods = {}

    memblock.methods.__init = terra(self : &memblock)
        self.ptr = nil
        self.size = 0
        self.allocator = nil
    end

    memblock.staticmethods.new = terra(allocator : Allocator, size : size_t)
        var ptr = [&T](allocator:alloc(sizeof(T) * size))
        return memblock{ptr, size, &allocator}
    end

    memblock.methods.get = macro(function(self, i)
        return `self.ptr[i]
    end)

    memblock.methods.set = macro(function(self, i, v)
        return quote 
            self.ptr[i] = v
        end
    end)

    memblock.methods.size = macro(function(self)
        return `self.size
    end)

    memblock.metamethods.__getmethod = function(self, methodname)
        return self.methods[methodname] or self.staticmethods[methodname]
    end

    memblock.methods.__dtor = terra(self : &memblock)
        self.allocator:free(self.ptr)
    end

    return memblock
end


local Default = function(T)

    local struct default{
    }

    terra default:alloc(size: uint64): &opaque
        var alignment = 64 -- Memory alignment for AVX512    
        var ptr: &opaque = nil 
        var res = C.posix_memalign(&ptr, alignment, size)
        return ptr
    end

    terra default:free(ptr: &opaque)
        C.free(ptr)
    end



local memblk = MemoryBlock(double)

terra main()
    var a : alloc.Default
    var s = memblk.new(&a, 10)
    s:set(0, 1.0)
    s:set(1, 2.0)
    io.printf("value at 0 is: %f\n", s:get(0))
    io.printf("value at 1 is: %f\n", s:get(1))
    io.printf("size is: %d\n", s:size())
end

main()

