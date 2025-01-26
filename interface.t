local base = require("base")

local newinterface = terralib.memoize(function(name)
    local interface = terralib.types.newstruct(name)

    local mt = getmetatable(interface)

    function mt:isimplemented(T)
        for name, method in pairs(self.methods) do
            local Isig = method.type
            assert(
                T.methods[name],
                (
                    "Interface %s requires method %s"
                ):format(tostring(self), name)
            )
            -- TODO Support terraform functions via dispatch()
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
        end
        return true
    end

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
        for name, method in pairs(Self.methods) do
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
            assert(interface:isimplemented(from))
            local impl = terralib.newlist()
            for _, entry in ipairs(vtable.entries) do
                local name = entry.field
                impl:insert(from.methods[name])
            end
            local ftab = constant(`vtable {[impl]})
            return `to {[&opaque](exp), &ftab}
        else
            error("Cannot perform cast to dynamic interface")
        end

    end
    return interface
end)

return {
    newinterface = newinterface,
}
