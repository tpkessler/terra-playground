local concepts = require("concepts")

--lua function to create a concept. A concept defines a concept
--defines a compile-time predicate that defines an equivalence 
--relation on a set.
local concept = concepts.concept

--primitive number concepts
local Float32 = concept(float)
local Float64 = concept(double)

-- abstract floating point numbers
local Float = concept("Float")
Float.default = function(T) return T.name=="Float" end
Float.float = function(T) return T.name=="float" end
Float.double = function(T) return T.name=="double" end

print(Float(Float32))

terra sum :: {Float, Float} -> {Float}


terra main()
    var x : Float
end
