local io = terralib.includec("stdio.h")
local Interface, AbstractSelf = unpack(require("interface"))

local struct S{
    a: double
}

do
    -- Free function are not avaible outside, only via the overloaded function.
    local terra S_int(self: &S, a: int)
        self.a = 23
    end

    local terra S_double(self: &S, a: double)
        self.a = -23
    end

    -- Overloaded methods cannot be declared with the ":" notation, that is
    -- S:foo = ...
    -- Instead, we have to manually add them to the methods table of the struct
    S.methods.foo = terralib.overloadedfunction("foo", {S_int, S_double})
end

do
    -- We can always append definitions later
    local terra S_float(self: &S, a: float)
        self.a = 0
    end

    S.methods.foo:adddefinition(S_float)
end

terra S:bar()
    return 1
end

-- Interfaces can check for members or methods. The latter can also be
-- overloaded.
local function MyInterface(T)
    return Interface{
        foo = {&AbstractSelf, T} -> {},
        bar = &AbstractSelf -> int,
        a = double
    }
end

local InterfaceDouble = MyInterface(double)
local InterfaceInt = MyInterface(int)
local InterfaceFloat = MyInterface(float)
local InterfaceUInt = MyInterface(uint)

local res, msg = pcall(function(S) InterfaceDouble:isimplemented(S) end, S)
assert(res == true)
local res, msg = pcall(function(S) InterfaceInt:isimplemented(S) end, S)
assert(res == true)
local res, msg = pcall(function(S) InterfaceFloat:isimplemented(S) end, S)
assert(res == true)

local res, msg = pcall(function(S) InterfaceUInt:isimplemented(S) end, S)
assert(res == false)

terra main()
    var s = S {}
    s:foo(1)
    io.printf("Int %g\n", s.a)
    s:foo(1.0)
    io.printf("Double %g\n", s.a)
    s:foo(1.0f)
    io.printf("Float %g\n", s.a)
end

main()
