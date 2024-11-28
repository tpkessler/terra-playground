-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local fun = require("fun")

local function gettag(name)
    return setmetatable(
        {},
        {__tostring = function() return name end}
    )
end

local traittag = gettag("TraitTag")
local methodtag = gettag("MethodTag")

local function isconcept(C)
    return terralib.types.istype(C) and C:isstruct() and C.type == "concept"
end

local function isempty(tab)
    return rawequal(next(tab), nil)
end

local function iscollection(C)
    return (
        isconcept(C)
        and isempty(C.methods)
        and isempty(C.metamethods)
        and isempty(C.traits)
        and #C.entries == 0
    )
end

local function isrefprimitive(T)
    assert(terralib.types.istype(T))
    if T:ispointer() then
        return isrefprimitive(T.type)
    else
        return T:isprimitive()
    end
end

local is_specialized_over
-- Checks if T satifies a concept C if T is concrete type.
-- Checks if T is more specialized than C if T is a concept.
local function check(C, T, verbose)
    verbose = verbose == nil and false or verbose
    assert(isconcept(C))
    assert(terralib.types.istype(T))
    -- Quick exit if you check the concept against itsself. This is useful
    -- if the concept refers to itsself in a method declaration
    if C == T then
        return true
    end
    -- Primitive types don't have methods, so they have to appear in the
    -- friends table. Otherwise, they don't satisfy the concept.
    if isrefprimitive(T) then
        for F, _ in pairs(C.friends) do
            if is_specialized_over(T, F) then
                return true
            end
        end
        error(
            (
                "Concept %s is not satisfied by primitive type %s"
            ):format(tostring(C), tostring(T))
        )
    -- For concepts, T.friends has to be a subset of C.friends
    elseif isconcept(T) then
        for F, _ in pairs(T.friends) do
            assert(C.friends[F],
            (
                "Concept %s requires type %s as friend but that was not found"
                .. "in %s"
            ):format(tostring(T), tostring(F), tostring(C))
            )
        end
    elseif iscollection(C) then
        assert(C.friends[T],
            (
                "Concept %s does not have friend %s"
            ):format(tostring(C), tostring(T))
        )
    end
    -- From this point onwards, we assume that T is a struct
    -- and not a primitive type
    assert(T:isstruct())

    for trait, value in pairs(C.traits) do
        assert(
            T.traits[trait] ~= nil,
            (
                "Concept %s requires trait %s but that was not found for %s"
            ):format(tostring(C), trait, tostring(T))
        )
        if value ~= traittag then
            assert(
                T.traits[trait] == value,
                (
                    "Concept %s requires value %s for trait %s but found %s"
                ):format(
                    tostring(C),
                    tostring(value),
                    tostring(trait),
                    tostring(T.traits[trait])
                )
            )
        end
    end

    local function isrefself(T, S)
        assert(terralib.types.istype(S))
        if S:ispointer(S) then
            return isrefself(T, S.type)
        else
            return S == T
        end
    end

    local function check_sig(Csig, Tsig)
        local function go(Csig, Tsig)
            assert(
                #Csig.parameters == #Tsig.parameters,
                "Cannot compare signatures\n" ..
                tostring(Csig) .. "\n" ..
                tostring(Tsig)
            )
            -- Skip self argument
            for i = 2, #Csig.parameters do
                local Carg = Csig.parameters[i]
                local Targ = Tsig.parameters[i]
                assert(
                    -- We skip the concept check if the signature contains
                    -- a reference to the current type on which we check
                    -- the concept. Otherwise, we trigger an infinite recursion.
                    isrefself(T, Targ) or is_specialized_over(Targ, Carg),
                    (
                        "%s is not specialized over %s in slot %d " ..
                        "of signatures\n%s\n%s"
                    ):format(
                        tostring(Targ),
                        tostring(Carg),
                        i,
                        tostring(Csig),
                        tostring(Tsig)
                    )
                )
            end
            -- We don't check the return type as we have no control over it
            -- during the method dispatch.
            return true
        end
        local ok, ret = pcall(
            function(Csig, Tsig) return go(Csig, Tsig) end, Csig, Tsig
        )
        if verbose then
            print(ret)
        end
        return ok and ret
    end

    local function check_method(method, ref_sig)
        local func = C.methods[method]
        if T.methods[method] then
            if func ~= methodtag then
                local sig = T.methods[method].type
                return check_sig(ref_sig, sig)
            end
            return true
        else
            return false
        end
    end

    local function check_template(method, ref_sig)
        if T.templates and T.templates[method] then
            local methods = T.templates[method].methods
            local res = fun.any(
                function(func)
                    local sig = func.type
                    return check_sig(ref_sig, sig)
    			end,
    			fun.map(function(k, v) return k:signature() end, methods)
    		)
            return res
        else
            return false
        end
    end

    local res = fun.all(
        function(method, func)
            local ref_sig = func.type
            assert(
                check_method(method, ref_sig) or check_template(method, ref_sig),
                (
                    "Concept %s requires the method %s " ..
                    "but that was not found for %s"
                ):format(tostring(C), method, tostring(T))
            )
            return true
        end,
        C.methods
    )
    for method, _ in pairs(C.metamethods) do
        assert(
            T.metamethods[method],
            (
                "Concept %s requires metamethod %s but that was not found for %s"
            ):format(tostring(C), method, tostring(T))
        )
    end

    assert(#C.entries <= #T.entries,
        (
            "Need at least %d entries in struct but only %d given."
        ):format(#C.entries, #T.entries)
    )
    for _, ref_entry in pairs(C.entries) do
        local ref_name = ref_entry.field
        local ref_type = ref_entry.type
        local has_entry = false
        for _, entry in pairs(T.entries) do
            local name = entry.field
            local type = entry.type
            if name == ref_name then
                assert(is_specialized_over(type, ref_type),
                    (
                        "Concept %s requires entry named %s to satisfy %s " ..
                        "but found %s"
                    ):format(
                        tostring(C),
                        name,
                        tostring(ref_type),
                        tostring(type)
                    )
                )
                has_entry = true
                break
            end
        end
        assert(
            has_entry,
            (
                "Concept %s requires entry named %s " ..
                "but that was not found for %s"
            ):format(tostring(C), ref_name, tostring(T))
        )
    end
    return true
end

local function Base(C, custom_check)
    assert(
        terralib.types.istype(C) and C:isstruct(),
        "Only a struct can be turned into a concept"
    )
    -- custom_check = custom_check or check
    C.friends = terralib.newlist()
    C.traits = terralib.newlist()
    C.type = "concept"
    C.check = custom_check or check
    local mt = getmetatable(C)
    function mt:__call(T, verbose)
        verbose = verbose == nil and false or verbose
        local ok, ret = pcall(function(S) return self:check(S, verbose) end, T)
        -- ret returns a string with an error message ithat indicates the
        -- reason for a failed comparison. Useful for debugging.
        if verbose then
            print(ret)
        end
        return ok and ret
    end

    function C:inherit(D)
        for _, entry in pairs(D.entries) do
            C.entries:insert(entry)
        end
        for _, tab in pairs({"friends", "methods", "metamethods", "traits"}) do
            for k, v in pairs(D[tab]) do
                C[tab][k] = v
            end
        end
    end

    function C:addmethod(name, sig)
        self.methods[name] = sig or methodtag
    end

    function C:addmetamethod(name)
        self.metamethods[name] = methodtag
    end

    function C:addtrait(name, val)
        self.traits[name] = val or traittag
    end

    function C:addentry(name, typ)
        self.entries:insert({field = name, type = typ})
    end

    function C:addfriend(typ)
        self.friends[typ] = true
    end
end

local struct Any(Base) {}

function is_specialized_over(C1, C2)
	for _, C in pairs({C1, C2}) do
		assert(terralib.types.istype(C),
			"Argument " .. tostring(C) .. " is not a terra type!")
	end
    -- Any other concept is more specialized than "Any".
    if C2 == Any then
        return true
    end
    -- "Any" cannot be more specialized than any other concept.
    if C1 == Any then
        return false
    end
	if C1:ispointer() and C2:ispointer() then
		return is_specialized_over(C1.type, C2.type)
	end
    if isconcept(C2) then
        return C2(C1)
    elseif not isconcept(C1) then
        -- Both arguments are concrete types, so we can simply test for equality
        return C1 == C2
    else
        -- C2 is a concrete type but C1 is a concept, so C1 can only be
        -- specialized if the friends table as only a single entry which is C2
        -- and all other tables are empty.
        local len = fun.foldl(
            function(acc, T) return acc + 1 end, 0, C1.friends
        )
        if len > 1 then
            return false
        else
            local F, _ = next(C1.friends)
            return F == C2
        end
    end
end

local newconcept = function(name)
    local C = terralib.types.newstruct(name)
    Base(C)
    return C
end

local struct Vararg {}
Base(Vararg, function(self, ...) return true end)


local Bool = newconcept("Bool")
Bool:addfriend(bool)

local RawString = newconcept("RawString")
RawString:addfriend(rawstring)

local Float = newconcept("Float")
local F = {}
for suffix, T in pairs({["32"] = float, ["64"] = double}) do
	local name = "Float" .. suffix
	F[name] = newconcept(name)
    F[name]:addfriend(T)
    Float:addfriend(T)
end

local I = {}
for _, prefix in pairs({"", "u"}) do
	local cname = prefix:upper() .. "Integer"
	I[cname] = newconcept(cname)
	for _, suffix in pairs({8, 16, 32, 64}) do
		local name = prefix:upper() .. "Int" .. tostring(suffix)
		local terra_name = prefix .. "int" .. tostring(suffix)
		-- Terra primitive types are global lua variables
		local T = _G[terra_name] 
		I[name] = newconcept(name)
		I[name]:addfriend(T)
		I[cname]:addfriend(T)
	end
end

local function append_friends(C, D)
    for k, v in pairs(D.friends) do
        C.friends[k] = v
    end
end

local Integral = newconcept("Integral")
for _, C in pairs({I.Integer, I.UInteger}) do
    append_friends(Integral, C)
end

local Real = newconcept("Real")
for _, C in pairs({Float, I.Integer}) do
    append_friends(Real, C)
end

local Number = newconcept("Number")
for _, C in pairs({Float, I.Integer, I.UInteger}) do
    append_friends(Number, C)
end

local BLASNumber = newconcept("BLASNumber")
BLASNumber:addfriend(float)
BLASNumber:addfriend(double)

local Primitive = newconcept("Primitive")
for _, C in pairs({I.Integer, I.UInteger, Bool, Float}) do
	append_friends(Primitive, C)
end

return {
    Base = Base,
    isconcept = isconcept,
    newconcept = newconcept,
    methodtag = methodtag,
    traittag = traittag,
    is_specialized_over = is_specialized_over,
    Any = Any,
    Vararg = Vararg,
    Bool = Bool,
    RawString = RawString,
    Float = Float,
    Float32 = F.Float32,
    Float64 = F.Float64,
    Integer = I.Integer,
    UInteger = I.UInteger,
    Int8 = I.Int8,
    Int16 = I.Int16,
    Int32 = I.Int32,
    Int64 = I.Int64,
    UInt8 = I.UInt8,
    UInt16 = I.UInt16,
    UInt32 = I.UInt32,
    UInt64 = I.UInt64,
    Integral = Integral,
    Real = Real,
    BLASNumber = BLASNumber,
    Number = Number,
    Primitive = Primitive,
}
