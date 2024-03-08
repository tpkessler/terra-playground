require("export_decl")
terralib.linklibrary("./libexport.so")

local function load_external_implementation(func, name)
	assert(terralib.isfunction(func), tostring(func) .. " is not a function")
	name = name or func.name

	assert(func:isdefined() == false,
		"Cannot load external implementation as "
		.. func.name .. " already has an implementation")

	local impl = terralib.externfunction(name, &func.type)
	func:adddefinition(impl)

	assert(func:isdefined())
end

for _, f in pairs(_G) do
	if terralib.isfunction(f) then
		load_external_implementation(f)
	end
end

local io = terralib.includec("stdio.h")
terra main()
	io.printf("Test addtwo\n")
	io.printf("%d %d %d\n", 1, 2, addtwo(1, 2))
	io.printf("Test setone_float\n")
	setone_float(nil)
	io.printf("Test setone_double\n")
	setone_double(nil)
	foo()
end
main()
