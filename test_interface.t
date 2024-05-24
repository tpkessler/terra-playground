import "terratest/terratest"

local interface = require("interface")

A = interface.Interface:new{
	add_one = {} -> {},
	inc = int -> double,
}

testenv "Working interface" do
	local struct Full {
	}
	terra Full:add_one() end
	terra Full:inc(y: int) return 1.0 end
    local ok, ret = pcall(function(T) A:isimplemented(T) end, Full)
    test ok == true
end

testenv "No methods" do
	local struct NoMethods {
	}
    local ok, ret = pcall(function(T) A:isimplemented(T) end, NoMethods)
    test ok == false
 
    local i, j = string.find(ret, "is not implemented for type")
    test i > 1
	test j > 1
end

testenv "Wrong return type" do
	local struct WrongReturn {
	}
	terra WrongReturn:add_one() end
	terra WrongReturn:inc(y: int) return 1 end
    local ok, ret = pcall(function(T) A:isimplemented(T) end, WrongReturn)
    test ok == false
 
    local i, j = string.find(ret, "Expected signature")
    test i > 1
	test j > 1
end

testenv "Too many parameters" do
	local struct TooMany {
	}
	terra TooMany:add_one(x: double) end
	terra TooMany:inc(y: int) return 1.0 end
    local ok, ret = pcall(function(T) A:isimplemented(T) end, TooMany)
    test ok == false

    local i, j = string.find(ret, "Expected signature")
    test i > 1
	test j > 1
end
