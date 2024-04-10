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


isfloat = concept()

isfloat.default = function (T) return false end 
isfloat.double = function (T) return true end 
isfloat.float = function (T) return true end

import "terratest/terratest"

testenv "Concept float" do

    t = isfloat(double, double)
    test t==false

    t = isfloat("string")
    test t==false

    t = isfloat(int)
    test t==false

    t = isfloat(bool)
    test t==false

    t = isfloat(double)
    test t==true

    t = isfloat(float)
    test t==true

end