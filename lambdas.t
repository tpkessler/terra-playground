-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

--lua function that generates a terra type that are function objects. these wrap
--a function in the 'apply' metamethod and store any captured variables in the struct
--as entries

local template = require("template")

local newtype = function(captures_t)
    local lambda = terralib.types.newstruct("lambda")
    --add captured variable types as entries to the wrapper struct
    for i,tp in ipairs(captures_t) do
        lambda.entries:insert({field = "_"..tostring(i-1), type = tp})
    end
    lambda:setconvertible("tuple")
    return lambda
end

local generate = function(fun, ...)
    --get the captured variables
    local captures = terralib.newlist{...}
    local captures_t = captures:map(function(v) return v:gettype() end)
    --get struct with captures
    local lambda = newtype(captures_t)
    --overloading the call operator - making 'lambda' a function object
    lambda.metamethods.__apply = macro(terralib.memoize(function(self, ...)
        local args = terralib.newlist{...}
        return `fun([args], unpacktuple(self))
    end))
    --return function object
    return lambda
end

--return a function object with captured variables in ...
local new = macro(function(fun, ...)
    --get the captured variables
    local captures = {...}
    local p = generate(fun, ...)
    --create and return lambda object by value
    return quote
        var f = p{[captures]}
    in
        f
    end
end)

return {
    new = new,
    generate = generate
}