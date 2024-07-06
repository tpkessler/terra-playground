--load 'terralibext' to enable raii
require "terralibext"
local interface = require("interface")
local err = require("assert")

local C = terralib.includecstring[[
	#include <stdio.h>
	#include <stdlib.h>
    #include <string.h>
]]

local size_t = uint64
local byte = uint8
local u8 = uint8
local u16 = uint16
local u32 = uint32
local u64 = uint64

--opaque allocator object with a handle to the concrete 
--allocator instance. 
local struct allochandle{
    handle : &opaque        --handle to the allocator instance
	fhandle : &opaque    	--pointer to its '__allocators_best_friend' method
}

--abstraction of a memory block. 
--'Allocators' are factories of 'SmartBlock(opaque)'.
--'metamethods.__cast' casts 'SmartBlock(opaque)' automatically to 'SmartBlock(T)'.
--'SmartBlock(T)' for a concrete type 'T' can be used as a smart pointer in containers.
--'methods.__init' and 'methods.__dtor' enable RAII
local SmartBlock = terralib.memoize(function(T)

    --abstraction of memory block
    --if T is a primitive type or a terra vector then we may use alignfac to
    --control the alignment of the memory block using 'alignment = sizeof(T) * alignfac' 
	local struct block{
    	ptr : &T                --Pointer to the actual data
    	alloc : &allochandle    --Handle to opaque allocator object
        alignfac : uint8        --factor that can be used to control alignment
	}

	--type traits
	block.isblock = true
	block.type = block
	block.eltype = T
    
    block.methods.isempty = terra(self : &block)
		return self.ptr==nil and self.alloc == nil
	end

    -- sizeof(T) if T is a concrete type
    local elsize = T==opaque and 1 or sizeof(T)

	block.methods.size = terra(self : &block) : size_t
        if not self:isempty() then
            return ([&u8](self.alloc) - [&u8](self.ptr)) / elsize
        end
        return 0
	end
	block.methods.size:setinlined(true)

	block.methods.__init = terra(self : &block)
		self.ptr = nil
		self.alloc = nil
        self.alignfac = 0
	end

	block.methods.__dtor = terra(self : &block)
		--using 'self.alloc.fhandle' function pointer to 
		--deallocate 'self'
		if not self:isempty() then
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
				--debug check if sizes are compatible, that is, is the
				--remainder zero after integer division
				err.assert((blk:size() * Size1) % Size2  == 0)
			in
				B {[&T2](blk.ptr), blk.alloc, blk.alignfac}
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

local DefaultAllocator = function(options)
  
    --get input options
    local options = options or {}
    local Alignment = options.alignment or 64 --Memory alignment for AVX512 == 64
    local Initialize = options.initialize or false
    
    --check input options
    assert(Alignment >= 0 and Alignment % 8 == 0)   --alignment is a multiple of 8 bytes
    assert(type(Initialize) == "boolean")   --initialize memory or not

    local terra round_to_aligned(size : size_t, alignment : size_t) : size_t
        return  ((size + alignment - 1) / alignment) * alignment
    end

    --allocate lambda, used to get a uniform api
    local terra __allocate :: {size_t, size_t} -> {&opaque}

    if Alignment == 0 then --use natural alignment
        if not Initialize then
            terra __allocate(size : size_t, counter : size_t)
                return C.malloc(size * counter)
            end
        else --initialize to zero using 'calloc'
            terra __allocate(size : size_t, counter : size_t)
                return C.calloc(counter, size)
            end
        end
    else --use user defined alignment (multiple of 8 bytes)
        if not Initialize then
            terra __allocate(size : size_t, counter : size_t)
                return C.aligned_alloc(Alignment, round_to_aligned(size * counter, Alignment))
            end
        else --initialize to zero using 'memset'
            terra __allocate(size : size_t, counter : size_t)
                var len = round_to_aligned(size * counter, Alignment)
                var ptr = C.aligned_alloc(Alignment, len)
                C.memset(ptr, 0, len)
                return ptr
            end
        end
    end

    --the default allocator
    local struct default{
    }

    terra default:owns(mem : &block) : bool
        if not mem:isempty() then
            return self == [&default](mem.alloc.handle)
        end
        return false
    end

    --single method that can allocate, free and reallocate memory
    --this method mirrors the 'lua_Alloc' function, 
    --see also 'https://nullprogram.com/blog/2023/12/17/'
    --a pointer to this method is set to block.alloc.fhandle
    terra default:__allocators_best_friend(mem : &block, newsize : size_t)
        if mem:isempty() and newsize > 0 then
            --allocate new memory
            --self:__allocate(mem, newsize)
        else
            if newsize == 0 then
                --free memory
                C.printf("Calling allocators best friend\n")
                self:deallocate(mem)
            elseif newsize > mem:size() then
                --reallocate memory
            end
        end
    end

    terra default:deallocate(mem : &block)
        C.printf("Calling deallocate default:deallocate\n")
        if self:owns(mem) then
            C.printf("Freeing memory\n")
            C.free(mem.ptr)
            mem:__init()
        end
    end

    --get a function pointer to 'default:__allocators_best_friend'
    local allocators_best_friend = constant(default.methods.__allocators_best_friend:getpointer())

    terra default:allocate(size : size_t, count : size_t)    
        --var ptr : &opaque = nil
        --allocate memory for the data ('size * count' bytes) and storage
        --of two pointers (2*8 bytes), the allocator handle and its function pointer
        var ptr = C.aligned_alloc(Alignment, round_to_aligned(size * count + 16, Alignment))
        --create handle to allocater 'self' and its allocation function pointer
        --these form a sentinal to the memory data, which means they are placed
        --right after the 'size * count' bytes of data, to define memory block 'size'
        var sentinal : &allochandle = nil
        if ptr~=nil then
            sentinal = [&allochandle]([&byte](ptr) + size * count)
            sentinal.handle = [&opaque](self)
            sentinal.fhandle = [&opaque](allocators_best_friend)
        end
        return block{ptr, sentinal}
    end

    --sanity check - is the allocator interface implemented
    Allocator:isimplemented(default)

    return default
end

return {
	block = block,
    SmartBlock = SmartBlock,
    Allocator = Allocator,
    DefaultAllocator = DefaultAllocator
}