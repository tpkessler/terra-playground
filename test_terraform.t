import "terraform"
local io = terralib.includec("stdio.h")


local template = require("template_new")
local concept = require("concept")

local Float = concept.Float
local Real = concept.Real

local ns = {}
ns.bar = {}

terraform ns.bar.foo(a : T, b : T, c : int) where {T}
    return a * b + c
end


terra main()
    var y = ns.bar.foo(2.0, 3.0, 1)
    io.printf("value of y: %0.2f\n", y)
end
main()
