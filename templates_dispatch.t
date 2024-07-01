--load 'terralibext' to enable raii
require "terralibext"
local template = require("template")
local concept = require("concept")
local io = terralib.includec("stdio.h")

--abstract integers
local Integer = concept.Integer

local function AbstractStack(S)

    local T = double

    S.methods.__init = terra(self : &S)
        var x : T = 2.0
        self.data = &x
        self.size = 1
        io.printf("calling base initializer.\n")
    end

    S.methods.set = terra(self : &S, d : T)
        @self.data = d
    end

    S.methods.get = terra(self : &S)
        return @self.data
    end

    S.methods.size = terra(self : &S)
        return self.size
    end

    S.methods.__dtor = terra(self : &S)
        self.data = nil
        self.size = 0
        io.printf("calling base destructor.\n")
    end

end

function Stack(T)

    local Base = AbstractStack

    local struct stack(Base){
        data : &T
        size : uint64
    }

    local Stack = concept.Concept:new(stack)

    stack.generate = {}
    stack.generate.foo = template.Template:new()
    stack.generate.foo[Stack] = function(S)
        return terra (x : S) : T
            return @x.data * @x.data
        end
    end

    stack.metamethods.__methodmissing = macro(function(method,...)
        local f = stack.generate[method]
        if f then
            local args = terralib.newlist{...}
            local types = args:map(function(v) return v.tree.type end)
            local gen = f(unpack(types))     --get generated terra function  
            return `gen(args)        --call generated terra function on concrete type
        end
    end)

    return stack
end

local mystack = Stack(double)

terra main()
    var x : mystack
    io.printf("my data: %f\n", x:get())
    io.printf("my size: %d\n", x:size())
    io.printf("my foo: %f\n", x:foo())
end

main()
