local concepts = {}

function concept()
    local fns = {}
    local mt = {}
    
    local function oerror()
        return error("Invalid argument types to overloaded function")
    end
    
    function mt:__call(...)
        local arg = {...}
        local default = self.default
        
        local signature = {}
        for i,arg in ipairs {...} do
            signature[i] = arg.name
        end
        
        signature = table.concat(signature, ",")
        
        return (fns[signature] or self.default)(...)
    end
    
    function mt:__index(key)
        local signature = {}
        local function __newindex(self, key, value)
            signature[#signature+1] = key
            fns[table.concat(signature, ",")] = value
        end
        local function __index(self, key)
            signature[#signature+1] = key
            return setmetatable({}, { __index = __index, __newindex = __newindex })
        end
        return __index(self, key)
    end
    
    function mt:__newindex(key, value)
        fns[key] = value
    end
    
    return setmetatable({ default = oerror }, mt)
end


import "terratest/terratest"


is_float = concept()

is_float.default = function (T) return false end 
is_float.double = function (T) return true end 
is_float.float = function (T) return true end

testenv "Concept float" do

    t = is_float(double, double)
    test t==false

    t = is_float("string")
    test t==false

    t = is_float(int)
    test t==false

    t = is_float(bool)
    test t==false

    t = is_float(double)
    test t==true

    t = is_float(float)
    test t==true

end


is_int = concept()

is_int.default = function (T) return false end 
is_int.int8 = function (T) return true end 
is_int.int16 = function (T) return true end 
is_int.int32 = function (T) return true end 
is_int.int64 = function (T) return true end

testenv "Concept int" do

    t = is_int(int, int)
    test t==false

    t = is_int("string")
    test t==false

    t = is_int(bool)
    test t==false

    t = is_int(double)
    test t==false

    t = is_int(int)
    test t==true

    t = is_int(int8)
    test t==true

    t = is_int(int16)
    test t==true

    t = is_int(int32)
    test t==true

    t = is_int(int64)
    test t==true

end


is_real = concept()

is_real.default = function (...) return is_int(...) or is_float(...) end 


testenv "Concept real" do

    t = is_real(int, int)
    test t==false

    t = is_real("string")
    test t==false

    t = is_real(bool)
    test t==false

    t = is_real(double)
    test t==true

    t = is_real(int)
    test t==true

end


complex = require "complex-2"

is_complex = concept()
is_complex.default = function (T) 
    return T.name=="complex"
end

testenv "Concept complex" do

    t = is_complex(double)
    test t == false

    t = is_complex(complex(double))
    test t == true

    t = is_complex(complex(int))
    test t == true

end


is_complex_float = concept()
is_complex_float.default = function (T) 
    return is_complex(T) and is_float(T.scalar_type)
end

testenv "Concept complex float" do

    t = is_complex_float(complex(double))
    test t == true

    t = is_complex_float(complex(int))
    test t == false

end

is_number = concept()
is_number.default = function (...) 
    return is_real(...) or is_complex(...)
end

testenv "Concept number" do

    t = is_number("hello")
    test t == false

    t = is_number(bool)
    test t == false

    t = is_number(int)
    test t == true

    t = is_number(complex(double))
    test t == true

end
