-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

--lua function that generates a terra type that is a function objects. these wrap
--a function in the 'apply' metamethod and store any captured variables in the struct
--as entries
<<<<<<< HEAD
local lambdagenerator = function(args)
    local signature = args.signature or error("Provide a function signature.")
    local captvars = args.captures or {}
    local ncaptures = #captvars
    --wrapper struct
    local struct lambda{
        funobject : signature
        captures : tuple(unpack(captvars))
    }
    --overloading the call operator - making 'lambda' a function object
    lambda.metamethods.__apply = macro(terralib.memoize(function(self, ...)
        local args = terralib.newlist{...}
        local capt = terralib.newlist()
        for i=1,ncaptures do
            local field = "_"..tostring(i-1)
            capt:insert(quote in self.captures.[field] end)
        end
        return `self.funobject([args], [capt])
    end))
    --determine function return-type
    lambda.returntype = signature.type.returntype
    --determine parameter types and captured types
    local params = signature.type.parameters
    local nparams = #params
    local K = nparams-ncaptures
    lambda.parameters, lambda.captures = terralib.newlist{}, terralib.newlist{}
    for k=1,K do
        lambda.parameters:insert(params[k])
    end
    for k=K+1,nparams do
        lambda.captures:insert(params[k])
    end
=======

local template = require("template")

local function new(captures_t)
    local lambda = terralib.types.newstruct("lambda")
    --add captured variable types as entries to the wrapper struct
    for i,tp in ipairs(captures_t) do
        lambda.entries:insert({field = "_"..tostring(i-1), type = tp})
    end
    lambda:setconvertible("tuple")
    return lambda
end

local lambda_generator = function(fun, ...)
    --get the captured variables
    local captures = terralib.newlist{...}
    local captures_t = captures:map(function(v) return v:gettype() end)
    --get struct with captures
    local lambda = new(captures_t)
    --overloading the call operator - making 'lambda' a function object
    lambda.metamethods.__apply = macro(terralib.memoize(function(self, ...)
        local args = terralib.newlist{...}
        return `fun([args], unpacktuple(self))
    end))
>>>>>>> range-terraform
    --return function object
    return lambda
end

return {
    generate = lambdagenerator,
}