-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

--lua function that generates a terra type that are function objects. these wrap
--a function in the 'apply' metamethod and store any captured variables in the struct
--as entries

local ckecklambdaexpr = function(expr)
    if not (expr.tree and expr.tree.type and expr.tree.type:isstruct()) then
        error("Not a valid capture. " ..
              "The capture syntax uses named arguments as follows: " ..
              "{x = xvalue, ...}.", 2)
    end
end

local makelambda = function(fun, lambdaobj)
    --check capture object
    ckecklambdaexpr(lambdaobj)
    local lambdatype = lambdaobj:gettype()
    --overloading the call operator - making 'lambdaobj' a function object
    lambdatype.metamethods.__apply = macro(terralib.memoize(function(self, ...)
        local args = terralib.newlist{...}
        return `fun([args], unpackstruct(self))
    end))
    --add returntype and parameter info if available
    local funtype = fun:gettype()
    if funtype:ispointertofunction() then
        lambdatype.returntype = funtype.type.returntype
        local nargs = #funtype.type.parameters - #lambdatype.entries
        lambdatype.parameters = funtype.type.parameters:filteri(function(i,v) return i <= nargs end)
    end
    return lambdaobj
end

local function genempty()
    return terralib.types.newstruct()
end

--return a function object with captured variables in ...
local new = macro(function(fun, capture)
    local lambda = makelambda(fun, capture or quote var c: genempty() in c end)
    return `lambda
end)

return {
    new = new,
    makelambda = makelambda
}
