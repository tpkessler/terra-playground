-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concepts = require("concept-impl")

local type = function(f)
    local fc = terralib.memoize(f)
    local function call(...)
        local arg = terralib.newlist{...}
        local T
        if arg:exists(concepts.isconcept) then
            -- Give a unique name to the concept as the result of newconcept
            -- is cached based on its name.
            T = concepts.newconcept(
                "ParametrizedType[" .. tostring(f) .. "]" ..
                "(" .. table.concat(arg:map(tostring), ",") .. ")"
            )
        else
            T = fc(...)
        end
        T.generator = f
        T.parameters = arg
        return T
    end
    return call
end

return {
    type = type,
}

