-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

require "terralibext"

local C = terralib.includecstring[[
    #include <stdio.h>
    #include <string.h>
]]

local base = require("base")
local interface = require("interface")
local range = require("range")
local err = require("assert")

local size_t = uint64
local u8 = uint8

local function ismanaged(args)
    local T, method = args.type, args.method
    if not T:isstruct() then
        return false
    end
    terralib.ext.addmissing[method](T)
    if T.methods[method] then
        return true
    end
    return false
end

local function Base(block, T, options)

    local options = terralib.newlist(options)
    --cloning is the default copy-assignment
    options.copyby = options.copyby or "clone"
    --copy-assignment is one of the following three options
    assert(options.copyby == "move" or options.copyby == "view" or options.copyby == "clone")

    --type traits
    block.isblock = true
    block.type = block
    block.traits.eltype = T
    block.elsize = T==opaque and 1 or sizeof(T)

    block.methods.getdataptr = terra(self : &block)
        return self.ptr
    end

    --block is empty, no resource and no allocator
    block.methods.isempty = terra(self : &block)
        return self.ptr==nil
    end

    --resource is borrowed, there is no allocator
    --this represents a view of the data
    block.methods.borrows_resource = terra(self : &block)
        return self.ptr~=nil and self.alloc.data==nil
    end

    --resource is owned, there is an allocator
    block.methods.owns_resource = terra(self : &block)
        return self.ptr~=nil and self.alloc.data~=nil
    end

    block.methods.size_in_bytes = terra(self : &block) : size_t
        return self.nbytes
    end

    if T==opaque then
        block.methods.size = terra(self : &block) : size_t
            return self.nbytes
        end
    else
        block.methods.size = terra(self : &block) : size_t
            return self.nbytes / [block.elsize]
        end
    end

    --add raii move method
    terralib.ext.addmissing.__move(block)

    --initialize to empty block
    block.methods.__init = terra(self : &block)
        self.ptr = nil
        self.nbytes = 0
        self.alloc.data = nil
        self.alloc.tab = nil
    end

    --exact clone of the block
    block.methods.clone = terra(self : &block)
        --allocate memory for exact clone
        var newblk : block
        if not self:isempty() then
            self.alloc:__allocators_best_friend(&newblk, [ block.elsize ], self:size())
            if not newblk:isempty() then
                C.memcpy(newblk.ptr, self.ptr, self:size_in_bytes())
            end
        end
        return newblk
    end

    --specialized copy-assignment, moving resources over
    if options.copyby == "move" then

        block.methods.__copy = terra(from : &block, to : &block)
            --set to
            to.ptr = from.ptr
            to.nbytes = from.nbytes
            to.alloc = from.alloc
            --reset from
            from:__init()
        end

    --specialized copy-assignment, returning a non-owning view of the data
    elseif options.copyby == "view" then

        block.methods.__copy = terra(from : &block, to : &block)
            to.ptr = from.ptr
            to.nbytes = from.nbytes
            --no allocator
            to.alloc.data = nil
            to.alloc.tab = nil
        end

    --specialized copy-assignment, returning a deepcopy or clone
    elseif options.copyby == "clone" then

        block.methods.__copy = terra(from : &block, to : &block)
            @to = from:clone()
        end

    end

end

--abstraction of a memory block without any type information.
local struct block

local __Allocator = interface.Interface:new{
    __allocators_best_friend = {&block, size_t, size_t}->{}
}

struct block{
    ptr : &opaque
    nbytes : size_t
    alloc : __Allocator
}

function block.metamethods.__typename(self)
    return "block"
end

base.AbstractBase(block)

--add base functionality
Base(block, opaque)

--__dtor for opaque memory block
terra block.methods.__dtor(self : &block)
    if self:borrows_resource() then
        self:__init()
    elseif self:owns_resource() then
        self.alloc:__allocators_best_friend(self, 0, 0)
    end
end
block:complete()


--abstraction of a memory block with type information.
local SmartBlock = terralib.memoize(function(T, options)

    local struct block{
        ptr : &T
        nbytes : size_t
        alloc : __Allocator
    }

    function block.metamethods.__typename(self)
        return ("SmartBlock(%s)"):format(tostring(T))
    end

    base.AbstractBase(block)

    -- Cast block from one type to another
    function block.metamethods.__cast(from, to, exp)
        local function passbyvalue(to, from)
            if from:ispointertostruct() and to:ispointertostruct() then
                return false, to.type, from.type
            end
            return true, to, from
        end
        --process types
        local byvalue, to, from = passbyvalue(to, from)        
        --exit early if types do not match
        if not to.isblock or not from.isblock then
            error("Arguments to cast need to be of generic type SmartBlock.")
        end
        --perform cast
        if byvalue then
            --case when to.eltype is a managed type
            if ismanaged{type=to.traits.eltype, method="__init"} then
                return quote
                    var tmp = exp
                    --debug check if sizes are compatible, that is, is the
                    --remainder zero after integer division
                    err.assert(tmp:size_in_bytes() % [to.elsize]  == 0)
                    --loop over all elements of blk and initialize their entries 
                    var size = tmp:size_in_bytes() / [to.elsize]
                    var ptr = [&to.traits.eltype](tmp.ptr)
                    for i = 0, size do
                        ptr:__init()
                        ptr = ptr + 1
                    end
                in
                    [to.type]{[&to.traits.eltype](tmp.ptr), tmp.nbytes, tmp.alloc}
                end
            --simple case when to.eltype is not managed
            else
                return quote
                    var tmp = exp
                    --debug check if sizes are compatible, that is, is the
                    --remainder zero after integer division
                    err.assert(tmp:size_in_bytes() % [to.elsize]  == 0)
                in
                    [to.type]{[&to.traits.eltype](tmp.ptr), tmp.nbytes, tmp.alloc}
                end
            end
        else
            --passing by reference
            terralib.ext.addmissing.__forward(from.type)
            return quote
                --var blk = exp invokes __copy, so we turn exp into an rvalue such
                --that __copy is not called
                var blk = exp:__forward()
                err.assert(blk:size_in_bytes() % [to.elsize]  == 0)
            in
                [&to.type](blk)
            end
        end
    end --__cast

    function block.metamethods.__staticinitialize(self)

        --add methods, staticmethods and templates table and template fallback mechanism 
        --allowing concept-based function overloading at compile-time
        base.AbstractBase(block)

        --add base functionality
        Base(block, T, options)

        --setters and getters
        block.methods.get = terra(self : &block, i : size_t)
            err.assert(i < self:size())
            return self.ptr[i]
        end

        block.methods.set = terra(self : &block, i : size_t, v : T)
            err.assert(i < self:size())
            self.ptr[i] = v
        end

        block.metamethods.__apply = macro(function(self, i)
            return quote
                err.assert(i < self:size())
            in
                self.ptr[i]
            end
        end)

        block.staticmethods.frombuffer = terra(size: size_t, ptr: &T)
            var nbytes = size * sizeof(T)
            var b: block
            b.ptr = ptr
            b.nbytes = nbytes
            b.alloc.data = nil
            b.alloc.tab = nil
            return b
        end

        --iterator - behaves like a pointer and can be passed
        --around like a value, convenient for use in ranges.
        local struct iterator{
            parent : &block
            ptr : &T
        }

        terra block:getiterator()
            return iterator{self, self.ptr}
        end

        terra iterator:getvalue()
            return @self.ptr
        end

        terra iterator:next()
            self.ptr = self.ptr + 1
        end

        terra iterator:isvalid()
            return (self.ptr - self.parent.ptr) * [block.elsize] < self.parent.nbytes
        end
        
        block.iterator = iterator
        range.Base(block, iterator)

        terra block:reallocate(size : size_t)
            self.alloc:__allocators_best_friend(self, sizeof(T), size)
        end

        --declaring __dtor for use in implementation below
        terra block.methods.__dtor :: {&block} -> {}
        
        --implementation __dtor
        --ToDo: change recursion to a loop
        local terra __dtor(self : &block)
            --insert metamethods.__dtor if defined, which is used to introduce
            --side effects (e.g. counting number of calls for the purpose of testing)
            escape
                if block.metamethods and block.metamethods.__dtor then
                    emit quote
                        [block.metamethods.__dtor](self)
                    end
                end
            end
            --return if block is empty
            if self:isempty() then
                return
            end
            --initialize block and return if block borrows a resource
            if self:borrows_resource() then
                self:__init()
                return
            end
            --first destroy other memory block resources pointed to by self.ptr
            --ToDo: change recursion into a loop
            escape
                if ismanaged{type=T,method="__dtor"} then
                    emit quote
                        var ptr = self.ptr
                        for i = 0, self:size() do
                            ptr:__dtor()
                            ptr = ptr + 1
                        end
                    end
                end
            end
            --free current memory block resources
            self.alloc:__allocators_best_friend(self, 0, 0)
        end

        --call implementation
        terra block.methods.__dtor(self : &block)
            __dtor(self)
        end

    end --__staticinitialize

	return block
end)


return {
    block = block,
    SmartBlock = SmartBlock
}
