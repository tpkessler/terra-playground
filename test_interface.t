import "terratest/terratest"

local Interface, AbstractSelf = unpack(require("interface"))

A = Interface{
	add_one = &AbstractSelf -> {},
	inc = {&AbstractSelf, int} -> double,
	len = int64,
	acc = &double
}

testenv "Working interface" do
	local struct Full {
		len: int64,
		acc: &double
	}
	terra Full:add_one() end
	terra Full:inc(y: int) return 1.0 end
    local ok, ret = pcall(function(T) A:isimplemented(T) end, Full)
	print(ret)
    test ok == true
end

testenv "No methods" do
	local struct NoMethods {
		len: int64,
		acc: &double
	}
    local ok, ret = pcall(function(T) A:isimplemented(T) end, NoMethods)
    test ok == false
 
    local i, j = string.find(ret, "Missing method called")
    test i > 1
	test j > 1
end

testenv "No entries" do
	local struct NoEntries {
	}
	terra NoEntries:add_one() end
	terra NoEntries:inc(y: int) return 1.0 end
    local ok, ret = pcall(function(T) A:isimplemented(T) end, NoEntries)
    test ok == false
 
    local i, j = string.find(ret, "Cannot find struct entry named")
    test i > 1
	test j > 1
end

testenv "Wrong return type" do
	local struct WrongReturn {
		len: int64,
		acc: &double
	}
	terra WrongReturn:add_one() end
	terra WrongReturn:inc(y: int) return 1 end
    local ok, ret = pcall(function(T) A:isimplemented(T) end, WrongReturn)
    test ok == false
 
    local i, j = string.find(ret, "Wrong type for method")
    test i > 1
	test j > 1
end

testenv "Wrong entry type" do
	local struct WrongType {
		len: uint,
		acc: &double
	}
	terra WrongType:add_one() end
	terra WrongType:inc(y: int) return 1.0 end
    local ok, ret = pcall(function(T) A:isimplemented(T) end, WrongType)
    test ok == false
 
    local i, j = string.find(ret, "Wrong type for entry")
    test i > 1
	test j > 1
end

testenv "Too many parameters" do
	local struct TooMany {
		len: int64,
		acc: &double
	}
	terra TooMany:add_one(x: double) end
	terra TooMany:inc(y: int) return 1.0 end
    local ok, ret = pcall(function(T) A:isimplemented(T) end, TooMany)
    test ok == false

    local i, j = string.find(ret, "Wrong type for method")
    test i > 1
	test j > 1
end
