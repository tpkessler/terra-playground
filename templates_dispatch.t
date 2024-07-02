--load 'terralibext' to enable raii
require "terralibext"
local base = require("base")
local template = require("template")
local concept = require("concept")
local io = terralib.includec("stdio.h")


local function AbstractStack(S, T)

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

    local Base = function(S) AbstractStack(S, T) end

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
    stack.generate.foo[{Stack,Stack}] = function(S1,S2)
        return terra (x : S1, y : S2) : T
            return @x.data * @y.data
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

local struct X{}
X.staticmethods = {}

X.metamethods.__getmethod = function(self,methodname)
    print("called __getmethod for ".. tostring(methodname))
    local fnlike = self.methods[methodname] or self.staticmethods[methodname]
    if not fnlike and terralib.ismacro(self.metamethods.__methodmissing) then
        fnlike = terralib.internalmacro(function(ctx,tree,...)
            return self.metamethods.__methodmissing:run(ctx,tree,methodname,...)
        end)
    end
    return fnlike
end

X.metamethods.__methodmissing = macro(function(methodname,...)
    print("called __methodmissing for ".. tostring(methodname))
    local gen = X.generate[methodname]
    if gen then
        local args = terralib.newlist{...}
        local types = args:map(function(v) return v.tree.type end)
        local f = gen(unpack(types))     --get generated terra function  
--        if not X.staticmethods[methodname] then
--            X.staticmethods[methodname] = terralib.overloadedfunction(methodname)
--        end
--        X.staticmethods[methodname]:adddefinition(f)
        return `f(args)        --call generated terra function on concrete type
    end
end)

terra X.staticmethods.myterrafun(a : int, b : int)
    return a * b
end

local Integer = concept.Integer

X.generate = {}
X.generate.foo = template.Template:new()
X.generate.foo[Integer] = function(S)
    return terra (x : S)
        return x * x
    end
end
X.generate.foo[{Integer,Integer}] = function(S1,S2)
    return terra (x : S1, y : S2)
        return x * y
    end
end



local mystack = Stack(double)

terra main()
    var x : mystack
    var y : mystack
    x:set(3)
    y:set(4)
    io.printf("my data: %f\n", x:get())
    io.printf("my size: %d\n", x:size())
    io.printf("my foo: %f\n", x:foo())
    io.printf("my other foo: %f\n", x:foo(y))
    io.printf("my free function eval: %d\n", X.myterrafun(1,2))
    io.printf("my generated static function foo: %d\n", X.foo(2, 3))
    io.printf("my generated static function foo: %d\n", X.foo(2))
end

main()