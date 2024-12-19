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

local function printtable(t)
    for k,v in pairs(t) do
        print(tostring(k) .." = " ..tostring(v))
    end
    print()
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
    --check number of traits
    if C.traits and #C.traits > 0 then
        assert(#C.traits <= #T.traits,
            (
                "Need at least %d traits but only %d given."
            ):format(#C.traits, #T.traits)
        )
    end
    --traits comparison
    for trait, desired in pairs(C.traits) do
        assert(
            T.traits[trait] ~= nil,
            (
                "Concept %s requires trait %s but that was not found for %s"
            ):format(tostring(C), trait, tostring(T))
        )
        if desired ~= traittag then
            local actual = T.traits[trait]
            assert(
                -- Traits can also be lua values (numbers or strings).
                -- Thus, we first check for equality and then for concept
                -- specialization.
                actual == desired or is_specialized_over(actual, desired),
                (
                    "Concept %s requires value %s for trait %s but found %s"
                ):format(
                    tostring(C),
                    tostring(desired),
                    tostring(trait),
                    tostring(actual)
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

    local function check_overloaded_method(Cfunc, Tlist)
        local ref_sig = Cfunc.type
        local res = fun.any(
                        function(func)
                            local sig = func.type
                            return check_sig(ref_sig, sig)
                		end,
                        Tlist
                    )
        return res
    end

    local function check_method(method)
        local conceptfun, typefun = C.methods[method], T.methods[method]
        if not typefun then
            return false
        end
        if conceptfun == methodtag then
            return true
        end
        assert(
            not terralib.ismacro(typefun),
            (
                "%s requires concrete method for %s but type %s " ..
                "defines it as a macro"
            ):format(tostring(C), method, tostring(T))
        )
        if terralib.isoverloadedfunction(typefun) then
            return check_overloaded_method(conceptfun, typefun.definitions)
        else
            local ref_sig = conceptfun.type
            return check_sig(ref_sig, typefun.type)
        end
    end

    local function check_template(method)
        if not T.templates then
            return false
        end
        local conceptfun, typefun = C.methods[method], T.templates[method]
        if not typefun then
            return false
        end
        if conceptfun == methodtag then
            return true
        end
        local res = check_overloaded_method(
                        conceptfun,
                        fun.map(
                            function(sig, func)
                                return sig:signature()
                            end,
                            typefun.methods
                        )
                    )
        return res
    end

    --check all methods
    local res = fun.all(
        function(method, func)
            assert(
                check_method(method) or check_template(method),
                (
                    "Concept %s requires the method %s " ..
                    "but that was not found for %s"
                ):format(tostring(C), method, tostring(T))
            )
            return true
        end,
        C.methods
    )
    --check all metamethods
    for method, _ in pairs(C.metamethods) do
        assert(
            T.metamethods[method],
            (
                "Concept %s requires metamethod %s but that was not found for %s"
            ):format(tostring(C), method, tostring(T))
        )
    end

    --check number of struct entries
    if T:isstruct() then 
        assert(#C.entries <= #T.entries,
            (
                "Need at least %d entries in struct but only %d given."
            ):format(#C.entries, #T.entries)
        )
    end
    --check individual struct entries
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
    C.traits = terralib.newlist()
    C.type = "concept"
    --add the custom check which evaluates a predicate returning true/false
    --or add default which is based on traits / methods / metamethods / entries
    if custom_check then
        C.check = function(C, T)
            if C ~= T then
                assert(custom_check(C, T))
            end
            return true
        end 
    else
        C.check = check
    end
    local mt = getmetatable(C)
    function mt:__call(T, verbose)
        verbose = verbose == nil and false or verbose
        local ok, ret = pcall(function(S) return self:check(S, verbose) end, T)
        -- ret returns a string with an error message that indicates the
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
        for _, tab in pairs({"methods", "metamethods", "traits"}) do
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

local newconcept = function(name, check)
    local C = terralib.types.newstruct(name)
    Base(C, check)
    return C
end

local struct Vararg {}
Base(Vararg, function(self, ...) return true end)

local Value = newconcept("Value")
Value.traits.value = traittag
--concept that carries a value, used to generate concept specialization
--with values (like integers or strings) rather that concepts.
local function ParametrizedValue(v)
	local C = newconcept(("Value(%s)"):format(tostring(v)))
	C.traits.value = v
	return C
end

return {
    Base = Base,
    newconcept = newconcept,
    isconcept = isconcept,
    is_specialized_over = is_specialized_over,
    Any = Any,
    Vararg = Vararg,
    Value = Value,
    ParametrizedValue = ParametrizedValue,
    traittag = traittag,
    methodtag = methodtag,
}
