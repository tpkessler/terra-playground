-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

--lua function that generates a terra type that is a function objects. these wrap
--a function in the 'apply' metamethod and store any captured variables in the struct
--as entries
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
    --return function object
    return lambda
end

return {
    generate = lambdagenerator,
}