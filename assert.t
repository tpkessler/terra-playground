-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

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

return S

