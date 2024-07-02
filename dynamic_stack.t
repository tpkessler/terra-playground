--load 'terralibext' to enable raii
require "terralibext"
local base = require("base")
local template = require("template")
local concept = require("concept")
local interface = require("interface")
local alloc = require("alloc")
local io = terralib.includec("stdio.h")



local Allocator = alloc.Allocator
local size_t = uint64

local Stacker = function(T) interface.Interface:new{
    size = {} -> int64,
    set = {concept.Integer, T} -> {},
    get = concept.Integer -> T
} end




local function DynamicStack(T)

    local struct stack{
        ptr : &T
        size : size_t
        allocator : &Allocator
    }

    stack.staticmethods = {}

    stack.staticmethods.new = terra(allocator : Allocator.type, length : size_t)
        io.printf("Calling allocator in new\n")
        var ptr = allocator:alloc(2*64)
        return ptr
    end

    stack.methods.get = terra(self : &stack, i : size_t)
        return self.ptr[i]
    end

    stack.methods.set = terra(self : &stack, i : size_t, v : T)
        self.ptr[i] = v
    end

    stack.metamethods.__getmethod = function(self, methodname)
        print("called __getmethod with ".. methodname)
        return self.methods[methodname] or self.staticmethods[methodname]
    end

    return stack
end


local stack = DynamicStack(double)


Allocator:isimplemented(alloc.Default)


terra main()
    var a : alloc.Default
    var s = stack.new(&a, 10)
--    s:set(0, 1.0)
--    s:set(1, 2.0)
--    io.printf("value at 0 is: %f\n", s:get(0))
--    io.printf("value at 1 is: %f\n", s:get(1))
end

main()

