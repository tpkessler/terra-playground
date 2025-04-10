local fun = require("fun")

local blend = function(check, istrue, isfalse)
    for _, arg in pairs{check, istrue, isfalse} do
        assert(terralib.isfunction(arg))
    end
    local ref = istrue.type.parameters
    for _, arg in pairs{check, istrue, isfalse} do
        local actual = arg.type.parameters
        assert(
            fun.all(function(T, S) return T == S end, fun.zip(ref, actual)),
            "Required signature " .. tostring(ref) .. " but got " .. tostring(actual)
        )
    end

    local sym = ref:map(symbol)
    return terra([sym])
        return terralib.select(
            [check]([sym]), [istrue]([sym]), [isfalse]([sym])
        )
    end
end

return {
    blend = blend,
}
