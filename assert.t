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
	    end -- if
    end -- quote
end) -- macro

S.error = macro(function(expr)
    local loc = expr.tree.filename..":"..expr.tree.linenumber
    return quote
	    C.printf("%s: %s\n", loc, expr)
	    C.abort()
    end -- quote
end) -- macro

S.NotImplementedError = macro(function() 
    return quote 
	    S.error("MethodError: Method is not implemented") 
    end
end)

return S

