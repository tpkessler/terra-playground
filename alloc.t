--load 'terralibext' to enable raii
require "terralibext"
local interface = require("interface")
local err = require("assert")

local C = terralib.includecstring[[
	#include <stdio.h>
	#include <stdlib.h>
    #include <string.h>
]]

-- terra does not import macros other than those that set a constant number
-- this causes an issue on macos, where 'stderr', etc are defined by referencing
-- to another implementation in a file. So we set them here manually. 
if rawget(C, "stderr") == nil and rawget(C, "__stderrp") ~= nil then
    rawset(C, "stderr", C.__stderrp)
end
if rawget(C, "stdin") == nil and rawget(C, "__stdinp") ~= nil then
    rawset(C, "stdin", C.__stdinp)
end 
if rawget(C, "stdout") == nil and rawget(C, "__stdoutp") ~= nil then
    rawset(C, "stdout", C.__stdoutp)
end 

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

    local T = T or opaque

    --abstraction of memory block
    --if T is a primitive type or a terra vector then we may use alignfac to
    --control the alignment of the memory block using 'alignment = sizeof(T) * alignfac' 
	local struct block{
    	ptr : &T                --Pointer to the actual data
    	alloc : &allochandle    --Handle to opaque allocator object
    }

    --only add setters and getters to the memory if the type
	--is known (so when its not an opaque type)
	
    function block.metamethods.__staticinitialize(self)

        --type traits
        block.isblock = true
        block.type = block
        block.eltype = T

        -- sizeof(T) if T is a concrete type
        block.methods.elsize = macro(function()
            if T==opaque then
                return `1
            else
                return `sizeof(T)
            end
        end)

        block.methods.isempty = terra(self : &block)
            return self.ptr==nil and self.alloc == nil
        end

        --akin to a weak pointer, which points to data but
        --is not allocated on the heap.
        block.methods.isweak = terra(self : &block)
            return self.ptr~=nil and self.alloc == nil
        end

        block.methods.bytes = terra(self : &block) : size_t
            if not self:isempty() then
                return ([&u8](self.alloc) - [&u8](self.ptr))
            end
            return 0
        end
        block.methods.bytes:setinlined(true)

        block.methods.size = terra(self : &block) : size_t
            err.assert(self:bytes() % self:elsize() == 0) 
            return self:bytes() / self:elsize()
        end
        block.methods.size:setinlined(true)

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

            block.metamethods.__apply = macro(function(self, i)
                return quote
                    err.assert(i < self:size())
                in
                    self.ptr[i]
                end
            end)
        end

        block.methods.__init = terra(self : &block)
            self.ptr = nil
            self.alloc = nil
        end

        terra block.methods.__dtor :: {&block}->{}


        block.methods.__dtor = terra(self : &block)
            --using 'self.alloc.fhandle' function pointer to 
            --deallocate 'self'
            if not self:isempty() then
                var free = [{&opaque, &block, size_t}->{}](self.alloc.fhandle)
                free(self.alloc.handle, self, 0)
            end
        end

        -- Cast block of one type to another
        function block.metamethods.__cast(from, to, exp)
            local pass_by_value = true
            if from:ispointertostruct() and to:ispointertostruct() then
                to, from = to.type, from.type
                pass_by_value = false
            end 
            if to.isblock and from.isblock then
                local B = to.type
                local T2 = to.eltype
                local Size2 = T2==opaque and 1 or sizeof(T2)
                if pass_by_value then
                    --passing by value
                    return quote
                        var blk = exp
                        --debug check if sizes are compatible, that is, is the
                        --remainder zero after integer division
                        err.assert(blk:bytes() % Size2  == 0)
                    in
                        B {[&T2](blk.ptr), blk.alloc}
                    end
                else
                    --passing by reference
                    return quote
                        var blk = exp
                        err.assert(blk:bytes() % Size2  == 0)
                    in
                        [&B](blk)
                    end
                end
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
    reallocate = {&block, size_t, size_t} -> {},
	deallocate = {&block} -> {},
	owns = {&block} -> {bool}
}
--an allator may also use one or more of the following options:
--Alignment (integer) -- use '0' for natural allignment and a multiple of '8' in case of custom alignment.
--Initialize (boolean) -- initialize memory to zero
--AbortOnError (boolean) -- abort behavior in case of unsuccessful allocation

local terra round_to_aligned(size : size_t, alignment : size_t) : size_t
    return  ((size + alignment - 1) / alignment) * alignment
end

local terra set_allochandle(ptr : &opaque, handle : &opaque, fhandle : &opaque, size : size_t) : &allochandle
    var sentinal : &allochandle = nil
    if ptr~=nil then
        sentinal = [&allochandle]([&byte](ptr) + size)
        sentinal.handle = handle
        sentinal.fhandle = fhandle
    end
    return sentinal
end

local terra abort_on_error(ptr : &opaque, size : size_t)
    if ptr==nil then
        C.fprintf(C.stderr, "Cannot allocate memory for buffer of size %g GiB\n", 1.0 * size / 1024 / 1024 / 1024)
        C.abort()
    end
end


local function AllocatorBase(A, Imp)

    terra A:owns(blk : &block) : bool
        if not blk:isempty() then
            return self == [&A](blk.alloc.handle)
        end
        return false
    end

    --single method that can free and reallocate memory
    --this method is similar to the 'lua_Alloc' function,
    --although we don't allow allocation here. 
    --see also 'https://nullprogram.com/blog/2023/12/17/'
    --a pointer to this method is set to block.alloc.fhandle
    terra A:__allocators_best_friend(blk : &block, size : size_t, counter : size_t)
        var requested_bytes = size * counter
        if not blk:isempty() then
            if requested_bytes == 0 then
                --free memory
                self:deallocate(blk)
            elseif requested_bytes > blk:bytes() then
                --reallocate memory
                self:reallocate(blk, size, counter)
            end
        end
    end

    terra A:deallocate(blk : &block)
        err.assert(self:owns(blk))
        Imp.__deallocate(blk)
    end

    terra A:reallocate(blk : &block, size : size_t, newcounter : size_t)
        err.assert(self:owns(blk) and (blk:bytes() % size == 0))
        if not blk:isempty() and (blk:bytes() < size * newcounter)  then
            Imp.__reallocate(blk, size, newcounter)
        end
    end

    --get a function pointer to 'default:__allocators_best_friend'
    local allocators_best_friend = constant(A.methods.__allocators_best_friend:getpointer())

    terra A:allocate(size : size_t, count : size_t)    
        --allocate memory for the data ('size * count' bytes) and storage
        --of two pointers (2*8 bytes), the allocator handle and its function pointer
        var blk = Imp.__allocate(size, count)
        --create handle to allocater 'self' and its allocation function pointer
        --these form a sentinal to the memory data, which means they are placed
        --right after the 'size * count' bytes of data, to define memory block 'size'
        if not blk:isempty() then
            blk.alloc.handle = [&opaque](self)
            blk.alloc.fhandle = [&opaque](allocators_best_friend)
        end
        return blk
    end

end



local DefaultAllocator = function(options)

    --get input options
    local options = options or {}
    local Alignment = options["Alignment"] or 0 --Memory alignment for AVX512 == 64
    local Initialize = options["Initialize"] or false -- initialize memory to zero
    local AbortOnError = options["Abort on error"] or true -- abort behavior

    --check input options
    assert(Alignment >= 0 and Alignment % 8 == 0)   --alignment is a multiple of 8 bytes
    assert(type(Initialize) == "boolean")
    assert(type(AbortOnError) == "boolean")

    --static abort behavior
    local __abortonerror = macro(function(ptr, size)
        if AbortOnError then
            return `abort_on_error(ptr, size)
        end
    end)

    --low-level functions that need to be implemented
    local Imp = {}
    terra Imp.__allocate :: {size_t, size_t} -> {block}
    terra Imp.__reallocate :: {&block, size_t, size_t} -> {}
    terra Imp.__deallocate :: {&block} -> {}

    if Alignment == 0 then --use natural alignment
        if not Initialize then
            terra Imp.__allocate(size : size_t, counter : size_t)
                var ptr = C.malloc(size * counter + 16)
                __abortonerror(ptr, size * counter)
                var sen = set_allochandle(ptr, nil, nil, size * counter)
                return block{ptr, sen}
            end
        else --initialize to zero using 'calloc'
            terra Imp.__allocate(size : size_t, counter : size_t)
                var newcounter = round_to_aligned(size * counter + 16, size) / size
                var ptr = C.calloc(newcounter, size)
                __abortonerror(ptr, size * counter)
                var sen = set_allochandle(ptr, nil, nil, size * counter)
                return block{ptr, sen}
            end
        end
    else --use user defined alignment (multiple of 8 bytes)
        if not Initialize then
            terra Imp.__allocate(size : size_t, counter : size_t)
                var ptr = C.aligned_alloc(Alignment, round_to_aligned(size * counter + 16, Alignment))
                __abortonerror(ptr, size * counter)
                var sen = set_allochandle(ptr, nil, nil, size * counter)
                return block{ptr, sen}
            end
        else --initialize to zero using 'memset'
            terra Imp.__allocate(size : size_t, counter : size_t)
                var len = round_to_aligned(size * counter + 16, Alignment)
                var ptr = C.aligned_alloc(Alignment, len)
                __abortonerror(ptr, size * counter)
                C.memset(ptr, 0, len)
                var sen = set_allochandle(ptr, nil, nil, size * counter)
                return block{ptr, sen}
            end
        end
    end

    if Alignment == 0 then 
        --use natural alignment provided by malloc/calloc/realloc
        --reallocation is done using realloc
        terra Imp.__reallocate(blk : &block, size : size_t, newcounter : size_t)
            err.assert(blk:bytes() % size == 0) --sanity check
            var newsize = size * newcounter
            if not blk:isempty() and (blk:bytes() < newsize)  then
                var handle = blk.alloc.handle
                var fhandle = blk.alloc.fhandle
                blk.ptr = C.realloc(blk.ptr, newsize + 16)
                __abortonerror(blk.ptr, newsize)
                blk.alloc = set_allochandle(blk.ptr, handle, fhandle, newsize)
            end
        end
    else 
        --use user defined alignment (multiple of 8 bytes)
        --we just use __allocate to get correcly aligned memory
        --and then memcpy
        terra Imp.__reallocate(blk : &block, size : size_t, newcounter : size_t)
            err.assert(blk:bytes() % size == 0) --sanity check
            var newsize = size * newcounter
            if not blk:isempty() and (blk:bytes() < newsize)  then
                --get new resource using '__allocate'
                var tmpblk = __allocate(size, newcounter)
                __abortonerror(tmpblk.ptr, newsize)
                --copy bytes over
                if not tmpblk:isempty() then
                    C.memcpy(tmpblk.ptr, blk.ptr, blk:bytes())
                end
                --reset allocator handle and function handle
                tmpblk.alloc = set_allochandle(tmpblk.ptr, blk.alloc.handle, blk.alloc.fhandle, newsize)
                --free old resources
                blk:__dtor()
                --reset blk.ptr and blk.alloc
                blk.ptr = tmpblk.ptr; tmpblk.ptr = nil
                blk.alloc = tmpblk.alloc; tmpblk.alloc = nil
            end
        end
    end

    terra Imp.__deallocate(blk : &block)
        C.free(blk.ptr)
        blk.ptr = nil
        blk.alloc = nil
    end

    --local base class
    local Base = function(A) AllocatorBase(A, Imp) end

    --the default allocator
    local struct default(Base){
    }

    --sanity check - is the allocator interface implemented
    Allocator:isimplemented(default)

    return default
end

return {
	block = block,
    SmartBlock = SmartBlock,
    Allocator = Allocator,
    AllocatorBase = AllocatorBase,
    DefaultAllocator = DefaultAllocator
}
