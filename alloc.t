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

local atomics = require("atomics")
local base = require("base")
local serde = require("serde")
local interface = require("interface")
local smartmem = require("smartmem")
local err = require("assert")

import "terraform"

local size_t = uint64

--abstraction of opaque memory block used by allocators.
--allocators are factories for block
local block = smartmem.block

--allocator interface:
--'allocate' or 'deallocate' a memory block
--the 'owns' method enables composition of allocators
--and allows for a sanity check when 'deallocate' is called.
local Allocator = interface.newinterface("Allocator")
terra Allocator:new(elsize: size_t, counter: size_t): block end
terra Allocator:allocate(blk: &block, elsize: size_t, counter: size_t) end
terra Allocator:reallocate(blk: &block, elsize: size_t, counter: size_t) end
terra Allocator:deallocate(blk: &block) end
terra Allocator:owns(blk: &block): bool end
terra Allocator:__allocate(blk: &block, elsize: size_t, counter: size_t) end
terra Allocator:__reallocate(blk: &block, elsize: size_t, counter: size_t) end
terra Allocator:__deallocate(blk: &block) end
Allocator:complete()

--an allocator may also use one or more of the following options:
--Alignment (integer) -- use '0' for natural allignment and a multiple of '8' in case of custom alignment.
--Initialize (boolean) -- initialize memory to zero
--AbortOnError (boolean) -- abort behavior in case of unsuccessful allocation

local terra abort_on_error(ptr : &opaque, size : size_t)
    if ptr==nil then
        C.fprintf(C.stderr, "Cannot allocate memory for buffer of size %g GiB\n", 1.0 * size / 1024 / 1024 / 1024)
        C.abort()
    end
end

local terra round_to_aligned(size : size_t, alignment : size_t) : size_t
    return  ((size + alignment - 1) / alignment) * alignment
end

local concept RawAllocator
    terra Self:__allocate(blk: &block, elsize: size_t, counter: size_t) end
    terra Self:__reallocate(blk: &block, elsize: size_t, counter: size_t) end
    terra Self:__deallocate(blk: &block) end
end

--Base class to facilitate implementation of allocators.
local function AllocatorBase(A)
    assert(RawAllocator(A))

    terra A:owns(blk : &block)
        if blk:owns_resource() then
            return [&opaque](self) == blk.alloc.data
        else
            return false
        end
    end

    terra A:allocate(blk : &block, elsize : size_t, counter : size_t)
        err.assert(blk:isempty())
        self:__allocate(blk, elsize, counter)
        blk.alloc = self
    end

    terra A:new(elsize : size_t, counter : size_t) : block
        var blk : block
        self:allocate(&blk, elsize, counter)
        return blk
    end

    terra A:deallocate(blk : &block)
        err.assert(self:owns(blk))
        self:__deallocate(blk)
        blk:__init()
    end

    terra A:reallocate(blk : &block, elsize : size_t, newcounter : size_t)
        err.assert(self:owns(blk))
        var oldsz = blk:size_in_bytes()
        var newsz = elsize * newcounter
        if newsz > oldsz then
            self:__reallocate(blk, elsize, newcounter)
        end
    end

    --single method that can free and reallocate memory
    --this method is similar to the 'lua_Alloc' function,
    --although we don't allow allocation here (yet). 
    --see also 'https://nullprogram.com/blog/2023/12/17/'
    --a pointer to this method is set to block.alloc_f
    terra A:__allocators_best_friend(
        blk : &block,
        elsize : size_t,
        counter : size_t
    ): {}
        var requested_size_in_bytes = elsize * counter
        if blk:isempty() and requested_size_in_bytes > 0 then
            self:allocate(blk, elsize, counter)
        else
            if requested_size_in_bytes == 0 then
                self:deallocate(blk)
            elseif requested_size_in_bytes > blk:size_in_bytes() then
                self:reallocate(blk, elsize, counter)
            end
        end
    end
end

--implementation of the default allocator using malloc and free.
local DefaultAllocator = function(options)
    options = options or {}
    options.Alignment = options.Alignment or 0
    options.Initialize = options.Initialize or false
    options.AbortOnError = options.AbortOneError or true

    assert(options.Alignment >= 0 and options.Alignment % 8 == 0)
    assert(type(options.Initialize) == "boolean")
    assert(type(options.AbortOnError) == "boolean")

    local generate_type = terralib.memoize(function(options_str)
        local ok, options = serde.deserialize_table(options_str)
        assert(ok)
        local Alignment = options.Alignment
        local Initialize = options.Initialize
        local AbortOnError = options.AbortOnError

        local default = (
            terralib.types.newstruct(
                (
                    "LibC(Alignment=%d, Initialize=%s, AbortOnError=%s)"
                ):format(Alignment, Initialize, AbortOnError)
            )
        )
        default:complete()

        terra default:__allocate(blk: &block, elsize: size_t, counter: size_t)
            var sz = elsize * counter
            var ptr: &opaque
            escape
                if Alignment ~= 0 then
                    emit quote 
                        var newsz = round_to_aligned(sz, Alignment) / elsize
                        ptr = C.aligned_alloc(Alignment, newsz * elsize) 
                    end
                else
                    emit quote ptr = C.malloc(sz) end
                end
                if AbortOnError then
                    emit `abort_on_error(ptr, sz)
                end
                if Initialize then
                    emit `C.memset(ptr, 0, sz)
                end
            end
            blk.ptr = ptr
            blk.nbytes = sz
        end

        terra default:__reallocate(
            blk: &block,
            elsize: size_t,
            newcounter: size_t
        )
            var sz = elsize * newcounter
            var ptr: &opaque
            escape
                if Alignment ~= 0 then
                    emit quote
                        var newsz = round_to_aligned(sz, Alignment) / elsize
                        ptr = C.aligned_alloc(Alignment, newsz * elsize)
                        C.memcpy(ptr, blk.ptr, blk.nbytes)
                        C.free(blk.ptr)
                    end
                else
                    emit quote ptr = C.realloc(blk.ptr, sz) end
                end
                if AbortOnError then
                    emit `abort_on_error(ptr, sz)
                end
            end
            blk.ptr = ptr
            blk.nbytes = sz
        end

        terra default:__deallocate(blk : &block)
            C.free(blk.ptr)
        end

        AllocatorBase(default)
        assert(Allocator:isimplemented(default))

        return default
    end)

    local options_str = serde.serialize_table(options)
    return generate_type(options_str)
end

require "terralibext"

local TracingAllocator = terralib.memoize(function()
    local struct tracing {
        A: Allocator
        used: uint64
    }

    function tracing.metamethods.__typename()
        return "TracingAllocator"
    end

    base.AbstractBase(tracing)

    local stream = global(&C.FILE)
    local default_stream = `C.stderr
    tracing.staticmethods.getstream = terra()
        return stream
    end

    tracing.staticmethods.setstream = terra(locstream: &C.FILE)
        stream = locstream
    end

    tracing.staticmethods.resetstream = terra()
        stream = [default_stream]
    end

    local default_stream = `C.stderr
    terra tracing:__init()
        tracing.setstream([default_stream])
        self.A.data = nil
        self.A.ftab = nil
        self.used = 0
    end

    terra tracing:__dtor()
        C.fprintf(
            stream,
            "TRACING ALLOCATOR: Reachable bytes %zu\n",
            self.used
        )
    end

    tracing.staticmethods.from = terra(A: Allocator)
        var tr: tracing
        tr.A = A
        return tr
    end

    terra tracing:__allocate(blk: &block, elsize: size_t, counter: size_t)
        self.A:__allocate(blk, elsize, counter)
        atomics.add(&self.used, blk:size_in_bytes())
    end

    terra tracing:__reallocate(blk: &block, elsize: size_t, counter: size_t)
        var oldsz: uint64
        atomics.store(&oldsz, blk:size_in_bytes())
        self.A:__reallocate(blk, elsize, counter)
        var sz: uint64
        atomics.store(&sz, blk:size_in_bytes())
        atomics.add(&self.used, sz - oldsz)
    end

    terra tracing:__deallocate(blk: &block)
        atomics.sub(&self.used, blk:size_in_bytes())
        self.A:__deallocate(blk)
    end

    AllocatorBase(tracing)
    assert(Allocator:isimplemented(tracing))

    return tracing
end)

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
    DefaultAllocator = DefaultAllocator,
    TracingAllocator = TracingAllocator,
}
