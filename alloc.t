--load 'terralibext' to enable raii
require "terralibext"
local interface = require("interface")
local err = require("assert")

local C = terralib.includecstring[[
	#include <stdio.h>
	#include <stdlib.h>
]]

local size_t = uint64
local byte = uint8
local u8 = uint8
local u16 = uint16
local u32 = uint32
local u64 = uint64

--opaque allocator object with a handle to the concrete 
--allocator instance. 
local struct __allocator{
    handle : &opaque        --handle to the allocator instance
	fhandle : &opaque    	--pointer to its '__allocators_best_friend' method
}

--abstraction of a memory block. 
--'Allocators' are factories of 'SmartBlock(opaque)'.
--'metamethods.__cast' casts 'SmartBlock(opaque)' automatically to 'SmartBlock(T)'.
--'SmartBlock(T)' for a concrete type 'T' can be used as a smart pointer in containers.
--'methods.__init' and 'methods.__dtor' enable RAII
local SmartBlock = terralib.memoize(function(T)

	--ToDo: remove 'size', place 'alloc' in the heap allocation
	--and use 'alloc.handle' as a sentinal to determine the size
	--of the allocation. Then 'sizeof(block) == 16' bytes and the
	--memory is always hot.
	local struct block{
    	ptr : &T
    	size : size_t
    	alloc : __allocator
	}

	--type traits
	block.isblock = true
	block.type = block
	block.eltype = T

	block.methods.size = terra(self : &block)
		return self.size
	end
	block.methods.size:setinlined(true)

	block.methods.isempty = terra(self : &block)
		return self:size()==0 and self.ptr==nil
	end

	block.methods.__init = terra(self : &block)
		self.ptr = nil
		self.size = 0
		self.alloc.handle = nil
		self.alloc.fhandle = nil
	end

	block.methods.__dtor = terra(self : &block)
		--using 'self.alloc.fhandle' function pointer to 
		--deallocate 'self'
		if self.alloc.handle ~= nil then
			var free = [{&opaque, &block, size_t}->{}](self.alloc.fhandle)
			free(self.alloc.handle, self, 0)
		end
	end

	--only add setters and getters to the memory if the type
	--is known (so when its not an opaque type)
	if T~=opaque then
		block.methods.get = terra(self : &block, i : size_t)
		    err.assert(i < self:size())
			return self.ptr[i]
		end
		block.methods.get:setinlined(true)

		block.methods.set = terra(self : &block, i : size_t, v : T)
			err.assert(i < self:size())
			self.ptr[i] = v
		end
		block.methods.set:setinlined(true)
	end

	-- Cast block of one type to another
	function block.metamethods.__cast(from, to, exp)
		if to.isblock and from.isblock then
			local B = to.type
			local T2 = to.eltype
			local T1 = from.eltype
			local Size1 = T1==opaque and 1 or sizeof(T1)
			local Size2 = T2==opaque and 1 or sizeof(T2)
			return quote
				var blk = exp
				var newsize = blk:size() * Size1 / Size2
				--debug check if sizes are compatible, that is, is the
				--remainder zero after integer division
				err.assert(newsize * Size2 == blk:size() * Size1)
			in
				B {[&T2](blk.ptr), newsize, blk.alloc}
			end
		end
	end

	return block
end)

--just a block of memory, no type information. This is what
--Allocators use. These 'typeless' blocks can be cast to 
--corresponding 'typed' blocks of the correct size.
local block = SmartBlock(opaque)

--allocator interface:
--'allocate' or 'deallocate' a memory block
--the 'owns' method enables composition of allocators
--and allows for a sanity check when 'deallocate' is called.
--ToDo: possibly add a realloc method?
local Allocator = interface.Interface:new{
	allocate = {size_t, size_t} -> {block},
	deallocate = {&block} -> {},
	owns = {&block} -> {bool}
}

--the default allocator
local struct default{
}

terra default:owns(mem : &block) : bool
    return self == [&default](mem.alloc.handle)
end

terra default:deallocate(mem : &block)
	C.printf("Calling deallocate default:deallocate\n")
    if self:owns(mem) then 
		C.printf("Freeing memory\n")
		C.free(mem.ptr)
		mem.ptr = nil
		mem.size = 0
		mem.alloc.handle = nil
		mem.alloc.fhandle = nil
	end
end

--single method that can allocate, free and reallocate memory
--this method mirrors the 'lua_Alloc' function, 
--see also 'https://nullprogram.com/blog/2023/12/17/'
--a pointer to this method is set to block.alloc.fhandle
terra default:__allocators_best_friend(mem : &block, newsize : size_t)
	if mem:isempty() then
		--allocate new memory
	else
		if newsize == 0 then
			--free memory
			self:deallocate(mem)
		elseif newsize > mem:size() then
			--reallocate memory
		end
	end
end

--get a function pointer to 'default:__allocators_best_friend'
local allocators_best_friend = constant(default.methods.__allocators_best_friend:getpointer())

terra default:allocate(size : size_t, count : size_t)
    var alignment = 64 -- Memory alignment for AVX512    
    var ptr : &opaque = nil
    --allocate memory for the data ('size * count' bytes) and storage
    --of two pointers (2*8 bytes), the allocator handle and its function pointer
    var res = C.posix_memalign(&ptr, alignment, size * count + 16)
    --create handle to allocater 'self' and its allocation function pointer
    --these form a sentinal to the memory data, which means they are placed
    --right after the 'size * count' bytes of data
    var sentinal = [&&opaque]([&byte](ptr) + size * count)
    sentinal[0] = [&opaque](self)
    sentinal[1] = [&opaque](allocators_best_friend)
    return block{ptr, size * count, __allocator{sentinal[0], sentinal[1]}}
end

--sanity check - is the allocator interface implemented
Allocator:isimplemented(default)

return {
	Allocator = Allocator,
	SmartBlock = SmartBlock,
	block = block,
	default = default
}