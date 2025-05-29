<!--
SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>

SPDX-License-Identifier: CC0-1.0
-->

# Design of allocators in terra
I briefly outline the design of the allocator class in 'alloc.t'

The overall design is based on the following key ideas:
* A container's `new` method (or any other factory function that returns a certain container object) takes an allocator as an opaque object that implements the allocator interface. This way, the allocator type is not part of the container type, which means that no template parameter is needed to enable generic allocators in containers. This is a serious issue in the c++ standard library where the allocator template parameter needs to be passed along with any container method. For more information on this issue check out the [BDE allocator model](https://github.com/bloomberg/bde/wiki/BDE-Allocator-Model).
* An abstraction of a memory block that has a notion of its allocator and a notion of its size. It can therefore 'free' its own resource when it runs out of scope or it can ask for additional resources when the current resource is too small. It can also be checked when a resource is borrowed (reference to allocator function handle is nil) or when a resource is owned (reference to allocator function handle is not nil). All is packed in an economical, single-function interface, ispired by 'lua_Alloc'. See also the [allocator API for C](https://nullprogram.com/blog/2023/12/17/).
* Every allocator has an 'owns' method, which enables composable allocators (see Andrei Alexandrescu's talk on [composable allocators in C++](https://www.youtube.com/watch?v=LIb3L4vKZ7U&t=21s)).


## Abstraction of a memory block
The proposed allocator API is centered around the abstraction of a memory `block`. Rather than only storing a pointer to the data it stores the size of the resource and a handle to its allocator and allocator/deallocator/reallocator function as follows:
```
local __Allocator = interface.Interface:new{
    __allocators_best_friend = {&block, size_t, size_t}->{}
}

local struct block{
    ptr : &T                --Pointer to the actual resource
    nbytes : size_t         --Number of bytes allocated
    alloc : __Allocator     --Handle to opaque allocator object
}

```
Here `alloc` is an opaque allocator object that implements the `__Allocator` interface, which contains a handle to the concrete allocator and a vtable containing a single function pointer that enables allocation / reallocation / deallocation of resources using just one function (`alloc` requires 16 bytes of storage - 8 for the handle to the allocator and 8 for the single function pointer).

This turns out to be very powerful. I'll cover the core advantages of this design.

### Ownership
We can make a distiction between blocks that are empty, ones that borrow a resource and ones that own a resource:
```
block.methods.isempty = terra(self : &block)
    return self.ptr==nil and self.alloc.handle==nil
end

block.methods.borrows_resource = terra(self : &block)
    return self.ptr~=nil and self.alloc.handle==nil
end

block.methods.owns_resource = terra(self : &block)
    return self.ptr~=nil and self.alloc.handle~=nil
end
```
Having access to the concrete allocator instance makes it easy to check for an allocator if it 'owns' a memory block. Given an allocator `A` the check is simply
```
terra A:owns(blk : &block) : bool
    if not blk:isempty() then
        return [&opaque](self) == [&opaque](blk.alloc.handle)
    end
    return false
end
```
This is powerful, because an `owns` method like this makes it possible to construct allocators that are compositions of others (see the talk of Andrei Alexandrescu on [composable allocators in C++](https://www.youtube.com/watch?v=LIb3L4vKZ7U&t=21s)).


### Deallocation
By implementing `__dtor` from the new RAII pull request, the handle to the concrete allocator instance allows the block to be freed automatically when it runs out of scope:
```
block.methods.__dtor = terra(self : &block)

    if self:isempty() then return end
    
    if self:borrows_resource() then
        self:__init()
        return
    end

    --run destructors of other smart-blocks that are referenced
    --by block.ptr (allowing destruction of e.g. linked lists)
    --even with cycles.
    ...
    ...
    ...
    
    --when the resource is owned, free the resource
    self.alloc:__allocators_best_friend(self, 0, 0)
end
```
Similarly, it can allocate (when block is empty) or reallocate itself with the same allocator when requested. I'll get back to the implementation of the method `__allocators_best_friend` shortly.

### Copy construction / assignment
A specialized copy assignment is implemented (from the new RAII pull request) that returns a non-owning view of the data
```
block.methods.__copy = terra(from : &block, to : &block)
    to.ptr = from.ptr
    to.nbytes = from.nbytes
    to.alloc.handle = nil       --reset the allocator handle to nil
    to.alloc.vtable = nil       --reset the vtable handle to nil
end
```
This means that a resource is only owned by a single object, resulting in safe resource management (no double free's, etc).

### Opaque blocks versus typed blocks and 
The standard `block`, used by allocators, is an opaque block (`T = opaque`). A `__cast` metamethod is implemented that can cast `block(opaque)` to any `block(T)`, thereby reinterpreting the memory. Such a typed block can be used in containers.

### Notion of size
The size of the allocated resource in terms of bytes is explicitly stored in the struct definition. The current size of a typed block in terms of number of elements `T` is then computed as
```
block.methods.size = terra(self : &block) : size_t
    return self.nbytes / [block.elsize]
end
```

## Design of allocators
Allocators follow a simple design: an allocator implements the following interface:
```
local Allocator = interface.Interface:new{
    allocate = {size_t, size_t} -> {block},
    reallocate = {&block, size_t, size_t} -> {},
    deallocate = {&block} -> {},
    owns = {&block} -> {bool}
}
```
where 'block = block(opaque)'.

Interfaces, such as the one here, are essentially opaque objects that are equiped with a vtable containing function pointers to the actual implementations at runtime. They can simply be passed by reference and do not require any template metaprogramming, since its based on runtime polymorphism.

The interface implementation will be provided as part of this library.

### Implementing a new allocator
Implementing a new allocator is easy. Given a struct
```
local myallocator = terralib.newstruct("myallocator")
```
the following (lowlevel) interface should be implemented:
```
myallocator.methods.__allocate :: {&block, size_t, size_t} -> {}   
myallocator.methods.__deallocate :: {&block} -> {}
myallocator.methods.__reallocate :: {&block, size_t, size_t} -> {}

```
Finally, by calling the following base class the implementation is completed:
```
AllocatorBase(myallocator)
```
For an example, please have a look at the corresponding implementation of the `DefaultAllocator` that uses malloc/free.

### The allocator base class
The allocator base class generates and completes the implementation of `myallocator`. It implements the following basic interfaces
```
function AllocatorBase(A)

    A.methods.owns :: {&A, blk : &block} -> bool
    
    A.methods.__allocators_best_friend :: {&A, &block, size_t, size_t} -> {}

    A.methods.allocate :: {&A, &block, size_t, size_t} -> {block}
    A.methods.deallocate :: {&A, &block} -> {}
    A.methods.reallocate :: {&A, &block, size_t, size_t} -> {}

end
```
We already covered the implementation of `owns`. The implementation of `__allocators_best_friend` is also straightforward. It looks like this:
```
terra A:__allocators_best_friend(blk : &block, size : size_t, counter : size_t)
    var requested_bytes = size * counter
    if blk:isempty() and requested_bytes > 0 then
        self:allocate(blk, size, counter)
    else
        if requested_bytes == 0 then
            --free memory
            self:deallocate(blk)
        elseif requested_bytes > blk:size_in_bytes() then
            --reallocate memory
            self:reallocate(blk, size, counter)
        end
    end
end
```
The idea of wrapping the three key allocator functions in one function is inspired from Lua's  lua_Alloc. See also the blog post on an [allocator API for C](https://nullprogram.com/blog/2023/12/17/).

Let's look at the `allocate` method:
```
terra A:allocate(blk : &block, elsize : size_t, counter : size_t)    
    var blk = Imp.__allocate(elsize, counter)
    blk.alloc = self
    return blk
end
```
The implementation of `__allocate`, `__reallocate` and `__deallocate` is specific to each allocator.

## Use in containers
Here follows an example of a simple `DynamicStack` class. A couple of interesting things are the following:
* The allocator is not passed as a template type parameter!
* A `__dtor` method need not be implemented to release the dynamic resources. One is generated automatically since `__dtor` is implemented for `block`.
* In `new` an opaque `block` is automatically cast to a `S = alloc.SmartBlock(T)`. 
* A `get` and `set` method is available for SmartBlock objects of type `S`. Essentially, `S = alloc.SmartBlock(T)` is a smart pointer type.
```
local alloc = require("alloc")

local Allocator = alloc.Allocator

local size_t = uint64

local DynamicStack = terralib.memoize(function(T)

    local S = alloc.SmartBlock(T)
    S:complete()

    local struct stack{
        data: S
    }

    stack.staticmethods = {}

    stack.staticmethods.new = terra(alloc : Allocator, size: size_t)
        return stack{alloc:allocate(sizeof(T), size)}
    end

    stack.metamethods.__getmethod = function(self, methodname)
        return self.methods[methodname] or stack.staticmethods[methodname]
    end

    terra stack:size()
        return self.data:size()
    end

    terra stack:get(i : size_t)
        return self.data:get(i)
    end

    terra stack:set(i : size_t, v : T)
        self.data:set(i, v)
    end

    return stack
end)
```
The above class can be used as follows:
```
local stack = DynamicStack(double)
local DefaultAllocator =  alloc.DefaultAllocator()

terra main()
    var alloc : DefaultAllocator
    var x = stack.new(&alloc, 2)
    x:set(0, 1.0)
    x:set(1, 2.0)
    io.printf("value of x[0] is: %f\n", x:get(0))
    io.printf("value of x[1] is: %f\n", x:get(1))
end
```

## Recursive datastructures
Recursive datastructures, such as linked lists can be implemented using specialized `__dtor`'s and keeping an array of nodes, or, directly, using smart blocks. The implementation of `block` supports automatic destruction of recursive datastructures, and even cycles. Here follows an example of a cyclical double linked list:

```
local alloc = require("alloc")

local DefaultAllocator = alloc.DefaultAllocator()
local Allocator = alloc.Allocator

--implementation of double-linked list
local struct d_node
local smrt_d_node = alloc.SmartBlock(d_node)

--metamethod used here for testing - counting the number
--of times the __dtor method is called
local smrt_d_node_dtor_counter = global(int, 0)
smrt_d_node.metamethods.__dtor = macro(function(self)
    return quote
        if self:owns_resource() then
            smrt_d_node_dtor_counter  = smrt_d_node_dtor_counter + 1
        end
    end
end)

smrt_d_node.metamethods.__entrymissing = macro(function(entryname, self)
    return `self.ptr.[entryname]
end)

smrt_d_node.metamethods.__methodmissing = macro(function(method, self, ...)
    local args = terralib.newlist{...}
    return `self.ptr:[method](args)
end)

struct d_node{
    index : int
    prev : smrt_d_node
    next : smrt_d_node
}
d_node:complete()


smrt_d_node.metamethods.__eq = terra(self : &smrt_d_node, other : &smrt_d_node)
    if not self:isempty() and not other:isempty() then
        return self.ptr == other.ptr
    end
    return false
end

terra smrt_d_node:allocate_next(A : Allocator)
    self.next = A:allocate(sizeof(d_node), 1)
    self.next.index = self.index + 1
    self.next.prev = self --create a view
end

terra smrt_d_node:set_next(next : &smrt_d_node)
    self.next = next  --create a view
end

terra smrt_d_node:set_prev(prev : &smrt_d_node)
    self.prev = prev  --create a view
end

terra main()
    smrt_d_node_dtor_counter = 0
    do
        --define head node
        var head : smrt_d_node = A:allocate(sizeof(d_node), 1)
        head.index = 0
        --make allocations
        head:allocate_next(&A)  --node 1
        head.next:allocate_next(&A) --node 2
        head.next.next:allocate_next(&A) --node 3
        --close loop
        head:set_prev(&head.next.next.next)
        head.next.next.next:set_next(&head) --node 3
    end
    return smrt_d_node_dtor_counter
end
--check that destructor is called four times
assert(main() == 4) 
```

## To do:
The following things remain:
* The current implementation of `block.methods.__dtor` relies on recursion. LLVM may not be able to fully optimize the recursion to a loop, which may seriously limit the size of such datastrutures due to limits in stack-space. In the near future I will rewrite the algorithm using a while loop.
* Right now only a default allocator is implemented based on `malloc`, `realloc`, `calloc` and `aligned_alloc`. Other standard allocators need to be implemented, such as, a 'stack', 'arena', 'freelist' allocators, etc.
* Functionality for composing allocators to build new ones.
* A `SmartBlock(T)` can already be cast to a `SmartBlock(vector(T))` for primitive types `T`. By adding a `__for` metamethod it would become possible to iterate over a `SmartBlock(vector(T))` and enable 'SIMD' instructions in a range for loop.
