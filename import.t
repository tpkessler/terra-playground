require("export_decl")

local uname = io.popen("uname","r"):read("*a")
if uname == "Darwin\n" then
	terralib.linklibrary("./libexport.dylib")
elseif uname == "Linux\n" then
	terralib.linklibrary("./libexport.so")
else
	error("OS Unknown")
end

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
	var mat32 = new_float(1)
	setone_float(mat32)
	del_float(mat32)
	io.printf("Test setone_double\n")
	var mat64 = new_double(2)
	setone_double(mat64)
	del_double(mat64)
end
main()
