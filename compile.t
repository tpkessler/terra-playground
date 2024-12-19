-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local types = {}
types[bool] = "bool"
types[rawstring] = "char *"
types[float] = "float"
types[double] = "double"
types[tuple()] = "void"
types[opaque] = "void"
types[&opaque] = "void *"

for _, pre in pairs{"", "u"} do
    for i = 0, 3 do
        local sz = 8 * 2 ^ i
        local locint = pre .. "int" .. sz
        local typ = _G[locint]
        types[typ] = locint .. "_t"
    end
end

local function toC(T)
    if T:ispointer() and not types[T] then
        local ref = 0
        while T:ispointer() do
            T = T.type
            ref = ref + 1
        end
        local TC = types[T]
        return TC .. " " .. string.rep("*", ref)
    else
        return types[T] or error("Unknown type " .. tostring(T))
    end
end

local function getCheader(methods)
    local headerfile = terralib.newlist()
    headerfile:insert("#pragma once")
    headerfile:insert("#include <stdint.h>")
    headerfile:insert("#include <stdbool.h>")
    for name, method in pairs(methods) do
        local param = method.type.parameters:map(toC)
        local returntype = toC(method.type.returntype)
        local func = ("%s %s(%s);"):format(returntype, name, param:concat(", ")) 
        headerfile:insert(func)
    end
    return headerfile:concat("\n")
end

local function generateCAPI(name, methods)
    local prototypes = getCheader(methods)
    local header = io.open(name .. ".h", "w")
    header:write(prototypes)
    header:close()
    terralib.saveobj(name .. ".o", methods)
end

return {
    getCheader = getCheader,
    generateCAPI = generateCAPI,
}
