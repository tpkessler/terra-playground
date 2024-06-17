local io = terralib.includec("stdio.h")
local concept = require("concept")
local template = require("template")

local function pimp_my_struct(S)
    assert(terralib.types.istype(S) and S:isstruct())
    -- Static methods
    rawset(S, "static_methods", {})
    -- Template magic
    rawset(S, "templates", {})
    -- Concept
    local Self = concept.Concept:new("Self", function(T) return T.type.name == S.name end)
    rawset(S, "Self", Self)

    S.metamethods.__methodmissing = macro(function(name, obj, ...)
        local is_static = (S.static_methods[name] ~= nil)
        local args = terralib.newlist({...})
        if is_static then
			args:insert(1, obj)
		end
		local types = args:map(function(t) return t.tree.type end)
		if is_static then
			local method = S.static_methods[name]
			return `method([args])
		else
			types:insert(1, &S)
			local method = S.templates[name]
			local func = method(unpack(types))
			return quote [func](&obj, [args]) end
		end
    end)

    return S
end

local struct S {
    a: int
}

S = pimp_my_struct(S)

terra S:add(b: int)
    self.a = self.a + b
end

S.static_methods.new = terra(a: int) return S {a} end
S.templates.copy = template.Template:new()
S.templates.copy[{S.Self, concept.Real}] = function(T1, T2)
    return terra(self: T1, a: T2)
        self.a = a
    end
end

terra foo(a: &int)
    @a = 32
end

terra main()
    var x = S.new(2)
    x:add(1)
    io.printf("Entry a is %d\n", x.a)
    x:copy(10)
    io.printf("Entry a is %d\n", x.a)

    return 0
end
main()
terralib.saveobj("modify", {main = main})

