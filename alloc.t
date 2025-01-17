-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

--load 'terralibext' to enable raii

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

local interface = require("interface")
local smartmem = require("smartmem")
local err = require("assert")

local size_t = uint64

--abstraction of opaque memory block used by allocators.
--allocators are factories for block
local block = smartmem.block

--allocator interface:
--'allocate' or 'deallocate' a memory block
--the 'owns' method enables composition of allocators
--and allows for a sanity check when 'deallocate' is called.
local Allocator = interface.Interface:new{
	new        = {size_t, size_t} -> {block},
    allocate   = {&block, size_t, size_t} -> {},
    reallocate = {&block, size_t, size_t} -> {},
	deallocate = {&block} -> {},
	owns       = {&block} -> {bool}
}

--an allocator may also use one or more of the following options:
--Alignment (integer) -- use '0' for natural allignment and a multiple of '8' in case of custom alignment.
--Initialize (boolean) -- initialize memory to zero
--AbortOnError (boolean) -- abort behavior in case of unsuccessful allocation

local terra round_to_aligned(size : size_t, alignment : size_t) : size_t
    return  ((size + alignment - 1) / alignment) * alignment
end

local terra abort_on_error(ptr : &opaque, size : size_t)
    if ptr==nil then
        C.fprintf(C.stderr, "Cannot allocate memory for buffer of size %g GiB\n", 1.0 * size / 1024 / 1024 / 1024)
        C.abort()
    end
end

--Base class to facilitate implementation of allocators.
local function AllocatorBase(A, Imp)

    terra A:owns(blk : &block) : bool
        if blk:owns_resource() then
            return [&opaque](self) == blk.alloc.data
        end
        return false
    end

    terra A:deallocate(blk : &block) : {}
        err.assert(self:owns(blk))
        Imp.__deallocate(blk)
    end

    terra A:reallocate(blk : &block, elsize : size_t, newcounter : size_t) : {}
        err.assert(self:owns(blk) and (blk:size_in_bytes() % elsize == 0))
        if not blk:isempty() and (blk:size_in_bytes() < elsize * newcounter)  then
            Imp.__reallocate(blk, elsize, newcounter)
            blk.alloc = self
        end
    end

    terra A:allocate(blk : &block, elsize : size_t, counter : size_t) : {}
        err.assert(blk:isempty())
        Imp.__allocate(blk, elsize, counter)
        blk.alloc = self
    end

    terra A:new(elsize : size_t, counter : size_t) : block
        var blk : block
        self:allocate(&blk, elsize, counter)
        return blk
    end

    --single method that can free and reallocate memory
    --this method is similar to the 'lua_Alloc' function,
    --although we don't allow allocation here (yet). 
    --see also 'https://nullprogram.com/blog/2023/12/17/'
    --a pointer to this method is set to block.alloc_f
    terra A:__allocators_best_friend(blk : &block, elsize : size_t, counter : size_t) : {}
        var requested_size_in_bytes = elsize * counter
        if blk:isempty() and requested_size_in_bytes > 0 then
            self:allocate(blk, elsize, counter)
        else
            if requested_size_in_bytes == 0 then
                --free memory
                self:deallocate(blk)
            elseif requested_size_in_bytes > blk:size_in_bytes() then
                --reallocate memory
                self:reallocate(blk, elsize, counter)
            end
        end
    end

end

--implementation of the default allocator using malloc and free.
local DefaultAllocator = terralib.memoize(function(options)

    --get input options
    local options = options or {}
    local Alignment = options["Alignment"] or 0 --Memory alignment for AVX512 == 64
    local Initialize = options["Initialize"] or false -- initialize memory to zero
    local AbortOnError = options["Abort on error"] or true -- abort behavior

    --check input options
    assert(Alignment >= 0 and Alignment % 8 == 0)   --alignment is a multiple of 8 size_in_bytes
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
    terra Imp.__allocate   :: {&block, size_t, size_t} -> {}
    terra Imp.__reallocate :: {&block, size_t, size_t} -> {}
    terra Imp.__deallocate :: {&block} -> {}
    
    if Alignment == 0 then --use natural alignment
        if not Initialize then
            terra Imp.__allocate(blk : &block, elsize : size_t, counter : size_t)
                err.assert(blk:isempty()) --sanity check
                var size_in_bytes = elsize * counter
                var ptr = C.malloc(size_in_bytes)
                __abortonerror(ptr, size_in_bytes)
                blk.ptr = ptr
                blk.nbytes = size_in_bytes
            end
        else --initialize to zero using 'calloc'
            terra Imp.__allocate(blk : &block, elsize : size_t, counter : size_t)
                err.assert(blk:isempty()) --sanity check
                var size_in_bytes = elsize * counter
                var ptr = C.calloc(counter, elsize)
                __abortonerror(ptr, size_in_bytes)
                blk.ptr = ptr
                blk.nbytes = size_in_bytes
            end
        end
    else --use user defined alignment (multiple of 8 size_in_bytes)
        if not Initialize then
            terra Imp.__allocate(blk : &block, elsize : size_t, counter : size_t)
                err.assert(blk:isempty()) --sanity check
                var newcounter = round_to_aligned(elsize * counter, Alignment) / elsize
                var size_in_bytes = newcounter * elsize
                var ptr = C.aligned_alloc(Alignment, size_in_bytes)
                __abortonerror(ptr, size_in_bytes)
                blk.ptr = ptr
                blk.nbytes = size_in_bytes
            end
        else --initialize to zero using 'memset'
            terra Imp.__allocate(blk : &block, elsize : size_t, counter : size_t)
                err.assert(blk:isempty()) --sanity check
                var newcounter = round_to_aligned(elsize * counter, Alignment) / elsize
                var size_in_bytes = newcounter * elsize
                var ptr = C.aligned_alloc(Alignment, size_in_bytes)
                __abortonerror(ptr, size)
                C.memset(ptr, 0, size_in_bytes)
                blk.ptr = ptr
                blk.nbytes = size_in_bytes
            end
        end
    end

    if Alignment == 0 then 
        --use natural alignment provided by malloc/calloc/realloc
        --reallocation is done using realloc
        terra Imp.__reallocate(blk : &block, elsize : size_t, newcounter : size_t)
            err.assert(blk:size_in_bytes() % elsize == 0) --sanity check
            var newsize_in_bytes = elsize * newcounter
            if blk:owns_resource() and (blk:size_in_bytes() < newsize_in_bytes)  then
                blk.ptr = C.realloc(blk.ptr, newsize_in_bytes)
                blk.nbytes = newsize_in_bytes
                __abortonerror(blk.ptr, newsize_in_bytes)
            end
        end
    else 
        --use user defined alignment (multiple of 8 size_in_bytes)
        --we just use __allocate to get correctly aligned memory
        --and then memcpy
        terra Imp.__reallocate(blk : &block, elsize : size_t, newcounter : size_t)
            err.assert(blk:size_in_bytes() % elsize == 0) --sanity check
            var newsize_in_bytes = elsize * newcounter
            if not blk:isempty() and (blk:size_in_bytes() < newsize_in_bytes)  then
                --get new resource using '__allocate'
                var tmpblk : block
                Imp.__allocate(&tmpblk, elsize, newcounter)
                __abortonerror(tmpblk.ptr, newsize_in_bytes)
                --copy size_in_bytes over
                if not tmpblk:isempty() then
                    C.memcpy(tmpblk.ptr, blk.ptr, blk:size_in_bytes())
                end
                --free old resources
                blk:__dtor()
                --move resources
                blk.ptr = tmpblk.ptr
                blk.nbytes = newsize_in_bytes
                blk.alloc = tmpblk.alloc
                tmpblk:__init()
            end
        end
    end
    
    terra Imp.__deallocate(blk : &block)
        C.free(blk.ptr)
        blk:__init()
    end

    --the default allocator
    local struct default{
    }

    --add functionality from base class
    AllocatorBase(default, Imp)

    --sanity check - is the allocator interface implemented
    Allocator:isimplemented(default)

    return default
end)

import "terraform"

--abstraction of a memory block with type information.
local SmartObject = terralib.memoize(function(obj, options)

    --SmartObject is a special SmartBlock
    local smrtobj = smartmem.SmartBlock(obj, options)

    --allocate an empty obj
    terraform smrtobj.staticmethods.new(A) where {A}
        var S: smrtobj = A:new(sizeof(obj), 1)
        return S
    end

    smrtobj.metamethods.__getmethod = function(self, methodname)
        local fnlike = self.methods[methodname] or smrtobj.staticmethods[methodname]
        --if no implementation is found try __methodmissing
        if not fnlike and terralib.ismacro(self.metamethods.__methodmissing) then
            fnlike = terralib.internalmacro(function(ctx, tree, ...)
                return self.metamethods.__methodmissing:run(ctx, tree, methodname, ...)
            end)
        end
        return fnlike
    end

    smrtobj.metamethods.__entrymissing = macro(function(entryname, self)
        return `self.ptr.[entryname]
    end)

    smrtobj.metamethods.__methodmissing = macro(function(method, self, ...)
        local args = terralib.newlist{...}
        return `self.ptr:[method](args)
    end)

    return smrtobj
end)

return {
    block = smartmem.block,
    SmartBlock = smartmem.SmartBlock,
    SmartObject = SmartObject,
    Allocator = Allocator,
    AllocatorBase = AllocatorBase,
    DefaultAllocator = DefaultAllocator
}
