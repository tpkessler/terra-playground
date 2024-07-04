--load 'terralibext' to enable raii
require "terralibext"
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
    deallocate : &opaque    --pointer to its 'deallocate' method
}

local function SmartBlock(T)

	local struct block{
    	ptr : &T
    	size : size_t
    	dealloc : deallocator
	}

	block.staticmethods = {}

	block.methods.__init = terra(self : &block)
		self.ptr = nil
		self.size = 0
		self.dealloc.handle = nil
		self.dealloc.deallocate = nil
	end

	block.methods.size = terra(self : &block)
		return self.size
	end
	block.methods.size:setinlined(true)

	block.methods.isempty = terra(self : &block)
		return self:size()==0 and self.ptr==nil
	end

	block.methods.__dtor = terra(self : &block)
		--using __allocators_best_friend function pointer to 
		--deallocate 'self'
		if self.dealloc.handle ~= nil then
			var free = [{&opaque, &block, size_t}->{}](self.dealloc.deallocate)
			free(self.dealloc.handle, self, 0)
		end
	end

	--only add setters and getters if the memory-layout of the type
	--is known (so when its not an opaque type)
	if T~=opaque then
		block.methods.get = terra(self : &block, i : size_t)
			return self.ptr[i]
		end
		block.methods.get:setinlined(true)

		block.methods.set = terra(self : &block, i : size_t, v : T)
			self.ptr[i] = v
		end
		block.methods.set:setinlined(true)
	end

	return block
end

--just a block of memory, no type information. This is what
--Allocators use. These 'typeless' blocks can be cast to 
--corresponding 'typed' blocks of the correct size.
local block = SmartBlock(opaque)

local Allocator = interface.Interface:new{
	allocate = {size_t, size_t} -> {block},
	deallocate = {&block} -> {},
	owns = {&block} -> {bool}
}

--default allocator
local struct default{
}

--check of 
terra default:owns(mem : &block) : bool
    return self == [&default](mem.dealloc.handle)
end

terra default:deallocate(mem : &block)
    if self:owns(mem) then 
		C.free(mem.ptr)
		mem.ptr = nil
		mem.size = 0
		mem.dealloc.handle = nil
		mem.dealloc.deallocate = nil
	end
end

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

local __allocators_best_friend = constant(default.methods.__allocators_best_friend:getpointer())

terra default:allocate(size : size_t, count : size_t)
    var alignment = 64 -- Memory alignment for AVX512    
    var ptr : &opaque = nil 
    var res = C.posix_memalign(&ptr, alignment, size * count)
    var deallocator = deallocator{[&opaque](self), [&opaque](__allocators_best_friend)}
    return block{ptr, size * count, deallocator}
end

Allocator:isimplemented(default)


return {
	Allocator = Allocator,
	default = default,
    block = block
}