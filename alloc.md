# Design of allocators in terra
I briefly outline the design of the allocator class in 'alloc.t'

The overall design is based on the following key ideas:
* A container's `new` method (or any other factory function that returns a certain container object) takes an allocator as an opaque object that implements the allocator interface. This way, the allocator type is not part of the container type, which means that no template parameter is needed to enable generic allocators in containers. This is a serious issue in the c++ standard library where the allocator template parameter needs to be passed along with any container method. For more information on this issue check out the [BDE allocator model](https://github.com/bloomberg/bde/wiki/BDE-Allocator-Model).
* An abstraction of a memory block that has a notion of its allocator and a notion of its size. It can therefore 'free' its own resource when it runs out of scope or it can ask for additional resources when the current resource is too small. It can also be checked when a resource is borrowed (reference to allocator is nil) or when a resource is owned (reference to allocator is not nil). All is packed in an economical, single-function interface, ispired by 'lua_Alloc'. See also the [allocator API for C](https://nullprogram.com/blog/2023/12/17/).
* Every allocator has an 'owns' method, which enables composable allocators (see Andrei Alexandrescu's talk on [composable allocators in C++](https://www.youtube.com/watch?v=LIb3L4vKZ7U&t=21s)).


## Abstraction of a memory block
The proposed allocator API is centered around the abstraction of a memory `block`. Rather than only storing a pointer to the data it stores a handle to its allocator as follows.
```
local struct block{
    ptr : &T                --Pointer to the actual data
    alloc : &allochandle    --Handle to opaque allocator object
}

local struct allochandle{
    handle : &opaque
	fhandle : {&opaque, &block, size_t, size_t}->{}
}
```
`allochandle` contains a handle to the concrete allocator instance and a function pointer `fhandle` that enables 'free', 'allocate' and 'reallocate' in one function. 

This turns out to be very powerful. For example, by implementing `__dtor` from the new RAII pull request, the handle to the concrete allocator instance allows the block to be freed automatically when it runs out of scope
```
block.methods.isempty = terra(self : &block)
    return self.ptr==nil and self.alloc == nil
end

block.methods.borrows_resource = terra(self : &block)
    return self.ptr~=nil and self.alloc == nil
end

block.methods.owns_resource = terra(self : &block)
    return self.ptr~=nil and self.alloc ~= nil
end

block.methods.__dtor = terra(self : &block)

    if self:isempty() then return end

    if self:borrows_resource() then 
        self.ptr = nil 
        return 
    end

    --run destructors of other smart-blocks that are referenced
    --by block.ptr (allowing destruction of linked lists)
    ...
    ...
    ...
    
    --when the resource is owned, free the resource
    self.alloc.fhandle(self.alloc.handle, self, 0, 0)
end
```
Similarly, it can allocate (when block is empty) or reallocate itself with the same allocator when requested. I'll get back to the implementation of the function pointer `fhandle` shortly.

The `alloc` pointer serves another purpose. By using the `alloc` pointer as a sentinal to the actual (heap) memory, the size in bytes can be computed simply as the pointer difference of `alloc` and `ptr`:
```
block.methods.size_in_bytes = terra(self : &block) : size_t
    if not self:isempty() then
        return ([&uint8](self.alloc) - [&uint8](self.ptr))
    end
    return 0
end
```

Finally, having access to the concrete allocator instance makes it easy to check for an allocator if it 'owns' a memory block. Given an allocator `A` the check is simply
```
terra A:owns(blk : block) : bool
    if not blk:isempty() then
        return self == [&A](blk.alloc.handle)
    end
    return false
end
```
This is powerful, because an `owns` method like this makes it possible to construct allocators that are compositions of others (see the talk of Andrei Alexandrescu on [composable allocators in C++](https://www.youtube.com/watch?v=LIb3L4vKZ7U&t=21s)).

## The allocator interface
An allocator implements the following interface:
```
local Allocator = interface.Interface:new{
	allocate = {size_t, size_t} -> {block},
    reallocate = {&block, size_t, size_t} -> {},
	deallocate = {&block} -> {},
	owns = {&block} -> {bool}
}
```
Interfaces, such as the one here, are essentially opaque objects that are equiped with a vtable containing function pointers to the actual implementations at runtime. They can simply be passed by reference and do not require any template metaprogramming, since its based on runtime polymorphism.

The interface implementation will be provided as part of this library.

## Implementing a new allocator
Implementing a new allocator is easy. Given a struct
```
    local myallocator = terralib.newstruct("myallocator")
```
the following (lowlevel) interface should be implemented:
```
    myallocator.methods.__allocate = {&block, size_t, size_t} -> {}   
    myallocator.methods.__deallocate = {&block} -> {}
    myallocator.methods.__reallocate = {&block, size_t, size_t} -> {}

```
Finally, by calling the following base class the implementation is completed:
```
    AllocatorBase(myallocator)
```

## The allocator base class
The allocator base class generates and completes the implementation of `myallocator`. It implements the following basic interfaces
```
function AllocatorBase(A)

    A.methods.owns = {blk : &block} -> bool
    
    A.methods.__fhandle = {&block, size_t, size_t} -> {}
    local fhandle = constant(A.methods.__fhandle:getpointer())

    A.methods.allocate = {size_t, size_t} -> {block}
    A.methods.deallocate = {&block} -> {}
    A.methods.reallocate = {&block, size_t, size_t} -> {}

end
```
We already covered the implementation of `owns`. The implementation of `__fhandle` is also straightforward. It looks like this:
```
terra A:__fhandle(blk : &block, size : size_t, counter : size_t)
    var requested_bytes = size * counter
    if blk:isempty() and requested_bytes > 0 then
        self:__allocate(blk, size, counter)
    else
        if requested_bytes == 0 then
            --free memory
            self:__deallocate(blk)
        elseif requested_bytes > blk:size_in_bytes() then
            --reallocate memory
            self:__reallocate(blk, size, counter)
        end
    end
end
```
The idea of wrapping the three key allocator functions in one function is inspired from Lua's  lua_Alloc. See also the blog post on an [allocator API for C](https://nullprogram.com/blog/2023/12/17/).

The variable `fhandle` stores a pointer to this function and can now be used in the implementation of `allocate`, `reallocate` or `free`. Let's look at the `allocate` method:
```
terra A:allocate(size : size_t, count : size_t)    
    var blk = block{}
    A:__allocate(&blk, size, count)
    if not blk:isempty() then
        blk.alloc.handle = [&opaque](self)
        blk.alloc.fhandle = [&opaque](allocators_best_friend)
    end
    return blk
end
```
The implementation of `__allocate` is specific to each allocator. However, it is required that `__allocate` creates the required buffer of memory for the data ('size * count' bytes) followed by storage of two pointers (2*8 bytes) for the allocator handle and its function pointer. Since the two pointers are placed right after the 'size * count' bytes of data, the memory block 'size' is implicitly defined by a pointer address difference.

## Typed blocks
Actually, `block` is generated by a call to the following Lua function:
```
local block = SmartBlock(opaque) 
```
A `__cast` metamethod is implemented that can cast `block` to any `SmartBlock(T)`, thereby reinterpreting the memory. Such a typed block can be used in containers.

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

## To do:
The following things remain:
* Right now only a default allocator is implemented based on `malloc`, `realloc`, `calloc` and `aligned_alloc`. Other standard allocators need to be implemented, such as, a 'stack', 'arena', 'freelist' allocators, etc.
* Functionality for composing allocators to build new ones.
* A `SmartBlock(T)` can already be cast to a `SmartBlock(vector(T))` for primitive types `T`. By adding a `__for` metamethod it would become possible to iterate over a `SmartBlock(vector(T))` and enable 'SIMD' instructions in a range for loop.