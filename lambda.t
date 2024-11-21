-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local interface = require("interface")
local fun = require("fun")

local function apply_from_eval(T)
    assert(terralib.types.istype(T) and T:isstruct())
    assert(T.methods.eval)
    T.metamethods.__apply = macro(function(self, ...)
        local  args = {...}
        return `self:eval([args])
    end)
end

local function entrymissing_from_get(T)
    assert(terralib.types.istype(T) and T:isstruct())
    T.metamethods.__entrymissing = macro(function(entryname, self)
        return `self:["get_" .. entryname]()
    end)
end

local function lambda(ref_sig, cap)
    cap = cap or struct {}
    local ref_methods = {eval = ref_sig}
    for _, e in ipairs(cap.entries) do
        ref_methods["get_" .. e.field] = {} -> e.type
    end
    local lambda = interface.Interface:new(ref_methods)
    apply_from_eval(lambda)
    entrymissing_from_get(lambda)

    lambda.staticmethods.new = macro(function(func, ...)
        local args = terralib.newlist({...})
        local capture = tuple(unpack(
                            args:map(function(a) return a:gettype() end)
                        ))
        local sig = func:gettype()
        local ref_param = ref_sig.type.parameters
        local param = sig.type.parameters
        for i, ref_typ in ipairs(ref_param) do
            local typ = param[i]
            assert(
                ref_typ == typ,
                (
                    "Lambda function expects type %s in argument %d" ..
                    " but got %s"
                ):format(tostring(ref_typ), i, tostring(typ))
            )
        end
        local ref_rettyp = ref_sig.type.returntype
        local rettyp = sig.type.returntype
        assert(
            ref_rettyp == rettyp,
            (
                "Lambda function expects return type %s" ..
                " but got %s"
            ):format(tostring(ref_rettyp), tostring(rettyp))
        )

        local sym = ref_param:map(function(T) return symbol(T) end)
        terra capture:eval([sym])
            return func([sym], unpacktuple(@self))
        end
        capture.methods.eval:setinlined(true)

        local param_type = fun.map(
                            function(v) return v.name, v.type end,
                            func.tree.value.definition.parameters
                           ):tomap()
        for i, entry in ipairs(cap.entries) do
            local desired = entry.type
            local actual = param_type[entry.field]
            assert(
                actual == desired,
                (
                    "Expected argument %s of type %s but got %s"
                ):format(entry.field, tostring(desired), tostring(actual))
            )
            local key = "get_" .. entry.field
            capture.methods[key] = terra(self: &capture)
                return self.["_" .. tostring(i - 1)]
            end
            capture.methods[key]:setinlined(true)
        end

        entrymissing_from_get(capture)
        apply_from_eval(capture)

        return `[capture] {[args]}
    end)

    return lambda
end

return {
    lambda = lambda
}
