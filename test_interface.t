import "terratest/terratest"

local interface = require("interface")

local struct A {
    x: double
}

terra A:add_one()
    self.x = self.x + 1.0
end

terra A:inc(y: int)
    self.x = self.x + y
    return self.x
end

local function FullyImplemented(T, I, R)
    I = I or int
    R = R or double
    local must_implement = {
        ["add_one"] = {&T} -> {},
        ["inc"] = {&T, I} -> R
    }
    interface.assert_implemented(T, must_implement)
    
    return true
end

local function MissingMethod(T)
    local must_implement = {
        ["mult"] = {&T, T} -> {T}
    }
    interface.assert_implemented(T, must_implement)

    return true
end

local function TooLongArgument(T)
    local must_implement = {
        ["add_one"] = {&T, int} -> {}
    }
    interface.assert_implemented(T, must_implement)
end

testenv "Working interface" do
    local ok, ret = pcall(FullyImplemented, A)
    test ok == true
end

testenv "No methods" do
    local ok, ret = pcall(FullyImplemented, int)
    test ok == false

    local len = #ret
    local i, j = string.find(ret, "Argument does not implement any methods")
    test i > 1
    test j == len
end

testenv "Wrong return type" do
    local ok, ret = pcall(FullyImplemented, A, int, float)
    test ok == false

    local len = #ret
    local i, j = string.find(ret, "Actual return type float doesn't match the desired double")
    test i > 1
    test j == len 
end

testenv "Missing method" do
    local ok, ret = pcall(MissingMethod, A)
    test ok == false

    local len = #ret
    local i, j = string.find(ret, "Missing implementation of mult for type A")
    test i > 1
    test j == len
end

testenv "Too many parameters" do
    local ok, ret = pcall(TooLongArgument, A)
    test ok == false

    local len = #ret
    local i, j = string.find(ret, "Number of function parameters don't match: Desired signature has 1 parameters but 2 were given")
    test i > 1
    test j == len
end
