-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concept = require("concept-impl")
local template = require("template")

local function isempty(tab)
    return next(tab) == nil
end

local function parametrizedconcept(name)
    local tp = template.Template:new()
    rawset(tp, "name", name)
    rawset(tp, "type", "parametrizedconcept")

    local mt = getmetatable(tp)
    -- templates already come with an overloaded __call. In contrast to
    -- function overloading we are not interested in the most specialized
    -- method but in all admissible methods because this includes inheritance
    -- of concept behavior.
    -- Instead of checking the most specialized combination of input arguments,
    -- specialization is defined by the number of equality constrained input
    -- arguments. The input {T, T} where {T: C} is considered to be specialized
    -- over {T1, T2} where {T1: C, T2: C}.
    function mt:__call(...)
        local arg = terralib.newlist({...})
        arg = arg:map(function(T) return template.cast_to_concept(T) end)
        local methods = self:get_methods(unpack(arg))
        assert(
            not isempty(methods),
            "No admissible implementation found for " .. tostring(arg) ..
            " in parametrized concept " .. self.name
        )
        local ref = template.paramlist.compress(arg)
        local name = ("%s(%s)"):format(
            self.name, arg:map(function(T) return tostring(T) end):concat(",")
        )
        local C = concept.newconcept(name)
        -- Get all admissible methods without constrained parameters, that is
        -- C(T, S) and C(T, S = T) are both included in the table.
        for sig, method in pairs(methods) do
            -- Only invoke methods that have at the least same number of
            -- constrained concepts.
            if #ref.keys <= #sig.keys then
                method(C, ...)
            end
        end
        return C
    end

    return tp
end

local function isparametrizedconcept(C)
    return type(C) == "table" and C.type == "parametrizedconcept"
end

return {
    parametrizedconcept = parametrizedconcept,
    isparametrizedconcept = isparametrizedconcept,
    paramlist = template.paramlist,
}

