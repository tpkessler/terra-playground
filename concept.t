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

local struct Vararg {}
Base(Vararg, function(self, ...) return true end)

local M = {
    Base = Base,
    isconcept = isconcept,
    methodtag = methodtag,
    traittag = traittag,
    is_specialized_over = is_specialized_over,
    Any = Any,
    Vararg = Vararg,
}

M.Bool = terralib.types.newstruct("Bool")
Base(M.Bool)
M.Bool.friends[bool] = true

M.RawString = terralib.types.newstruct("RawString")
Base(M.RawString)
M.RawString.friends[rawstring] = true

M.Float = terralib.types.newstruct("Float")
Base(M.Float)
struct M.Float(Base) {}
for suffix, T in pairs({["32"] = float, ["64"] = double}) do
	local name = "Float" .. suffix
	M[name] = terralib.types.newstruct(name)
    Base(M[name])
	M[name].friends[T] = true
	M.Float.friends[T] = true
end

for _, prefix in pairs({"", "u"}) do
	local cname = prefix:upper() .. "Integer"
	M[cname] = terralib.types.newstruct(cname)
    Base(M[cname])
	for _, suffix in pairs({8, 16, 32, 64}) do
		local name = prefix:upper() .. "Int" .. tostring(suffix)
		local terra_name = prefix .. "int" .. tostring(suffix)
		-- Terra primitive types are global lua variables
		local T = _G[terra_name] 
		M[name] = terralib.types.newstruct(name)
        Base(M[name])
		M[name].friends[T] = true
		M[cname].friends[T] = true
	end
end

local function append_friends(C, D)
    for k, v in pairs(D.friends) do
        C.friends[k] = v
    end
end

M.Integral = terralib.types.newstruct("Integral")
Base(M.Integral)
for _, C in pairs({M.Integer, M.UInteger}) do
    append_friends(M.Integral, C)
end

M.Real = terralib.types.newstruct("Real")
Base(M.Real)
for _, C in pairs({M.Float, M.Integer}) do
    append_friends(M.Real, C)
end

M.Number = terralib.types.newstruct("Number")
Base(M.Number)
for _, C in pairs({M.Float, M.Integer, M.UInteger}) do
    append_friends(M.Number, C)
end

M.BLASNumber = terralib.types.newstruct("BLASNumber")
Base(M.BLASNumber)
for _, T in pairs({float, double}) do
    M.BLASNumber.friends[T] = true
end

M.Primitive = terralib.types.newstruct("Primitive")
Base(M.Primitive)
for _, C in pairs({M.Integer, M.UInteger, M.Bool, M.Float}) do
	append_friends(M.Primitive, C)
end

return M
