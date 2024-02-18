local C = terralib.includecstring [[
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <stdarg.h>
]]

local S = {}


S.assert = macro(function(condition)
    local loc = condition.tree.filename..":"..condition.tree.linenumber
    return quote
	if not condition then
	    C.printf("%s: assertion failed!\n", loc)
    	    C.abort()
	end
    end
end)

S.error = macro(function(expr)
    local loc = expr.tree.filename..":"..expr.tree.linenumber
    return quote
	C.printf("%s: %s\n", loc, expr)
	C.abort()
    end   
end)

S.NotImplementedError = macro(function() 
    return quote 
	S.error("MethodError: Method is not implemented") 
    end
end)

S.printvararg = macro(function(...)
    local args = terralib.newlist {...}
    local fn = terralib.cast(args:map("gettype") -> {},print)
    return quote  
	fn([args])
    end                                                                                                                 
end) 

Varargs = terralib.memoize(function(T,N)
    local t = terralib.types.newstruct()
    for i = 1,N do
	t.entries:insert {"_"..(i-1), T}
    end
    t:setconvertible("tuple")
    return t
end)

local IVectorClass = {}

IVectorClass.generate = function(V, T, N)

    local self = {}
    
    self.Vector = V

    terra self.Vector:eltype() S.NotImplementedError() end
    terra self.Vector:size() S.NotImplementedError() end
    terra self.Vector:getindex(i : int) S.NotImplementedError() end
    terra self.Vector:setindex(v : T, i : int) S.NotImplementedError() end    

    return self
end


local VectorClass = {}

VectorClass.generate = function(T,N)

    local struct Vector{
	_data : T[N]
    }
    Vector:setconvertible("array")

    local self = IVectorClass.generate(Vector, T, N)

    terra self.Vector:getindex(i : int) : T
	S.assert(i < N)
      	return self._data[i]
    end

    terra self.Vector:setindex(v : T, i : int)
	S.assert(i < N)
	self._data[i] = v
    end

    terra self.Vector:address() : &T
        return &self._data[0]
    end

    terra self.Vector:size() : int
	return N 
    end

    self.create = macro(function(...)
	local args = {...}
    	return `self.Vector { arrayof(T,[args]) } 
    end)

    local exprlist = terralib.newlist()
    local v = symbol(T[N])
    local a = symbol(T)

    for i = 1, N do
	exprlist:insert(quote	
	    v[i-1] = [a]
	end)
    end
    terra self.fill([a])
	var [v]
	[exprlist]
	return self.Vector { [v] }
    end
	

    terra self.zeros()
	return self.fill(T(0))
    end

    terra self.ones()
	return self.fill(T(1.0))
    end

    terra self.indicator(k : int)
    	var v = self.zeros()
	v._data[k] = T(1)
	return v
    end


    terra self.dot(a : self.Vector, b : self.Vector) : T
      	return T(2)
    end

    Vector.metamethods.__apply = macro(function(self,idx)
	return `self:getindex(idx)
    end)

    function Vector.metamethods.__typename(self)
	return "Vector("..tostring(T)..","..tostring(N)..")"
    end

    

    return self
end



local SVec3d = VectorClass.generate(double, 3)

terra main()

    var z : Varargs(int,3) = {1,2,3}
    C.printf("Varargs values are (%d , %d , %d)\n", z._0, z._1, z._2)

    var b : int[2] = array(0,1)

    var x : tuple(int,int) = {1, 2}    
    C.printf("tuple is: (%d , %d)\n", x._0, x._1)

    var a = SVec3d.Vector { array(0.1,0.2,0.3) }
    C.printf("size of vector: %d\n", a:size())
  
    a:setindex(5.0,0) 
    C.printf("the value at index 0 is: %f\n", a:getindex(0))

    C.printf("the dot product is: %f\n", SVec3d.dot(a,a))

    C.printf("Value at index 2 is: %f\n", a(2))

    S.printvararg(1,2,3,4,5,6)

    C.printf("\n")
    var zz = SVec3d.create(5.1,1.0,2.0)
    C.printf("value of x at 0 is: %.2f\n", zz(0))

    var t = SVec3d.fill(4.0)
    C.printf("Value of t at index 2 is: %.2f\n", t(2))

    var y = SVec3d.zeros()
    C.printf("Vector y: [%.2f, %.2f, %.2f]\n", y(0), y(1), y(2))	

    var u = SVec3d.ones()
    C.printf("Vector u: [%.2f, %.2f, %.2f]\n", u(0), u(1), u(2))

    var w = SVec3d.indicator(1)
    C.printf("Vector w: [%.2f, %.2f, %.2f]\n", w(0), w(1), w(2))

end

main()
