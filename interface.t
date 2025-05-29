-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local base = require("base")
local templates = require("template")

local newinterface = terralib.memoize(function(name)
    local interface = terralib.types.newstruct(name)
    interface.type = "interface"

    local vtable = terralib.types.newstruct(name .. "Vtable")
    function interface.metamethods.__getentries(Self)
        for name, method in pairs(Self.methods) do
            vtable.entries:insert({field = name, type = &opaque})
        end
        vtable:complete()

        local entries = terralib.newlist()
        entries:insert({field = "data", type = &opaque})
        entries:insert({field = "ftab", type = &vtable})

        return entries
    end

    function interface.metamethods.__staticinitialize(Self)
        Self.interface_methods = {}
        for name, method in pairs(Self.methods) do
            Self.interface_methods[name] = method

            local sig = method.type
            local typ = terralib.newlist()
            typ:insertall(sig.parameters)
            typ[1] = &opaque
            local ret = sig.returntype

            local sym = typ:sub(2, -1):map(symbol)

            Self.methods[name] = terra(self: &Self, [sym])
                var func = [typ -> ret](self.ftab.[name])
                return func(self.data, [sym])
            end
        end
    end

    function interface.metamethods.__cast(from, to, exp)
        assert(to == interface)
        if from:ispointertostruct() then
            from = from.type
            local methods = assert(interface:isimplemented(from))
            local impl = terralib.newlist()
            for _, entry in ipairs(vtable.entries) do
                local name = entry.field
                impl:insert(methods[name])
            end
            local ftab = constant(`vtable {[impl]})
            return `to {[&opaque](exp), &ftab}
        else
            error("Cannot perform cast to dynamic interface")
        end

    end

    function interface:isimplemented(T)
        local methods = {}
        for name, method in pairs(self.interface_methods) do
            local Isig = method.type
            local Tmethod = T.methods[name]
            local Ttemplate = T.templates and T.templates[name]
            assert(
                Tmethod or Ttemplate,
                (
                    "Interface %s requires method %s"
                ):format(tostring(self), name)
            )

            if Tmethod then
                local Tsig = T.methods[name].type
                local are_same = true
                are_same = (#Isig.parameters == #Tsig.parameters) and are_same
                -- Skip self parameter
                for i = 2, #Isig.parameters do
                    are_same = (
                        (Isig.parameters[i] == Tsig.parameters[i]) and are_same
                    )
                end
                are_same = (Isig.returntype == Tsig.returntype) and are_same
                assert(
                    are_same,
                    (
                        "Interface %s method %s requires %s but given %s"
                    ):format(
                        tostring(self),
                        name,
                        tostring(Isig),
                        tostring(Tsig)
                    )
                )
                methods[name] = Tmethod
            else
                local args = terralib.newlist()
                args:insertall(Isig.parameters)
                -- For the method dispatch we have to replace the abstract
                -- self &interface with the concrete self &T.
                args[1] = &T
                local sig, method = Ttemplate(unpack(args))
                methods[name] = method
            end
        end
        return methods
    end

    return interface
end)

local function isinterface(I)
    return terralib.types.istype(I) and I.type == "interface"
end

return {
    newinterface = newinterface,
    isinterface = isinterface,
}
