-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local fun = require("luafun@v1/luafun")

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
    return next(tab) == nil
end

local function iscollection(C)
    return (
        isconcept(C)
        and isempty(C.methods)
        and isempty(C.metamethods)
        and isempty(C.traits)
        and C.generator == nil
        and isempty(C.parameters)
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
local function collectioncheck(C, D)
    -- Check for collections are different from methods or traits checks.
    -- The latter describe a logical "and" operation. This method AND that method
    -- or this trait AND that trait have to be satisfied if a concept comparison
    -- evaluates to true. However, collections represent a logical "OR".
    -- If given a collection and a concrete type, then the concept check already
    -- returns true if the concept check yields true on any of the friends.
    -- The situation complicates if we want to compare two collections, since
    -- we have to compare to logical "OR" operations. This means that in the
    -- concept comparison not all concepts are active for different inputs.
    -- There is no direct relation between the friends of one concept and
    -- the friends of the other side. If the "OR" operation evaluates to true
    -- we can't tell which of the friends has evaluated to true (for "AND",
    -- we know that _all_ need to evaluate to true). But when we put a restriction
    -- on the concepts, we can filter the relevant concepts. We require that
    -- the truth sets of the participating concepets on both sides either agree
    -- or are disjoint (atomic concepts). In this case, the logical "OR" can be tested
    -- by iterating over the atoms.
    -- If C = {R1, ..., RN} and D = {U1, ..., UM} are atomic, then D <= C if, and only if,
    -- for all i = 1, ..., M there exists j in {1, ..., N} with Ui <= Rj
    -- This is exactly what we check in the second branch of the logical or below.
    -- The first check is meant as a quick exit for types or concepts listed
    -- in the friends table without the need to iterate over all friends of
    -- the other argument.
    if iscollection(C) then
        if iscollection(D) then
            assert(
                fun.all(
                    function(U) return is_specialized_over(U, C) end,
                    D.friends
                ),
                "Argument " .. tostring(D) ..
                " is not satisfied by any of the elements in " .. tostring(C)
            )
        else
            assert(
                isempty(C.friends)
                or fun.any(
                    function(R) return is_specialized_over(D, R) end,
                    C.friends
                ),
                "Argument " .. tostring(D) ..
                " is not satisfied by any of the elements in " .. tostring(C)
            )
        end
    end
    return true
end

local traitcheck = function(C, T)
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
    return true
end

local generatorcheck = function(C, T)
    if not C.generator then
        return true
    end
    assert(
        C.generator == T.generator,
        (
            "Concept %s requires the same generator as %s"
        ):format(tostring(C), tostring(T))
    )
    assert(fun.all(
            function(D, S)
                return is_specialized_over(S, D)
            end,
            fun.zip(C.parameters or {}, T.parameters or {})
        ),
        (
            "Argument %s is not specialized over %s"
        ):format(tostring(T.parameters), tostring(C.parameters))
    )
    return true
end

local function isrefself(Self, T)
    assert(terralib.types.istype(Self))
    assert(terralib.types.istype(T))
    if T:ispointer() then
        return isrefself(Self, T.type)
    else
        return T == Self
    end
end

local function checksignature(Self, Csig, Tsig)
    if #Csig.parameters ~= #Tsig.parameters then
        return false
    end
    -- We don't check the return type as we have no control over it
    -- during the method dispatch.
    return fun.all(
        function(Targ, Carg)
            return isrefself(Self, Targ) or is_specialized_over(Targ, Carg)
        end,
        -- Skip self argument in method signature
        fun.zip(Tsig.parameters, Csig.parameters):drop(1)
    )
end

local methodtagcheck = function(C, T, name)
    return (
        C.methods[name] == methodtag
        and (T.methods[name] or (T.templates and T.templates[name]))
    )
end

local rawmethodcheck = function(C, T, name)
    local desired = C.methods[name].type
    local method = T.methods[name]
    -- method:isfunction() doesn't work on incomplete functions, so we simply
    -- check is method is a pointer, that is, if method.type exists.
    return method and method.type and checksignature(T, desired, method.type)
end

local overloadedcheck = function(C, T, name)
    local desired = C.methods[name].type
    local method = T.methods[name]
    return (
        terralib.isoverloadedfunction(method)
        and fun.any(
            function(actual)
                return checksignature(T, desired, actual.type)
            end,
            method.definitions
        )
    )
end

local templatecheck = function(C, T, name)
    local desired = C.methods[name].type
    local tmpl = T.templates and T.templates[name]
    if tmpl then
        return fun.any(
            function(actual)
                return checksignature(T, desired, actual)
            end,
            fun.map(
                function(compressed, func)
                    return compressed:signature().type
                end,
                tmpl.methods
            )
        )
    else
        return false
    end
end

local methodlookup = {
    raw = rawmethodcheck,
    overloaded = overloadedcheck,
    template = templatecheck,
}

local methodcheck = function(C, T)
    return fun.all(
        function(name, method)
            assert(
                methodtagcheck(C, T, name) or fun.any(
                    function(cname, check)
                        return check(C, T, name)
                    end,
                    methodlookup
                ),
                (
                    "Concept %s requires method %s but that was not found for %s"
                ):format(tostring(C), name, tostring(T))
            )
            return true
        end,
        C.methods
    )
end

local metamethodcheck = function(C, T)
    for name, _ in pairs(C.metamethods) do
        assert(
            T.metamethods[name],
            (
                "Concept %s requires metamethod %s but that was not found for %s"
            ):format(tostring(C), name, tostring(T))
        )
    end
    return true
end

local entrycheck = function(C, T)
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

local partialcheck = {
    collection = collectioncheck,
    trait = traitcheck,
    generator = generatorcheck,
    method = methodcheck,
    metamethod = metamethodcheck,
    entry = entrycheck,
}

local function Base(C, custom_check)
    assert(
        terralib.types.istype(C) and C:isstruct(),
        "Only a struct can be turned into a concept"
    )
    C.traits = terralib.newlist()
    C.friends = terralib.newlist()
    C.generator = nil
    C.parameters = terralib.newlist()
    C.type = "concept"
    C.custom_check = custom_check
    --add the custom check which evaluates a predicate returning true/false
    --or add default which is based on traits / methods / metamethods / entries
    if custom_check then
        function C:check(T)
            return assert(
                self == T or self:custom_check(T),
                "Custom check on " .. tostring(self) ..
                " and " .. tostring(T) .. " failed"
            )
        end
    else
        function C:check(T)
            return self == T or self.friends[T] or fun.all(
                function(name, pcheck) return pcheck(self, T) end, partialcheck
            )
        end
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
            self.entries:insert(entry)
        end

        self.generator = D.generator

        local entries = {
            "methods",
            "metamethods",
            "traits",
            "parameters",
        }
        for _, tab in pairs(entries) do
            for k, v in pairs(D[tab]) do
                self[tab][k] = v
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

local newconcepttype = terralib.memoize(function(name)
    return terralib.types.newstruct(name)
end)

local newconcept = function(name, check)
    local C = newconcepttype(name)
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
