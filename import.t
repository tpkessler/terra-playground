require("export_decl")
terralib.linklibrary("./libexport.so")

local function emit_wrapper(name, signature)
	local func = terralib.externfunction(name, signature)

	local arg_type = signature.type.parameters
	local arg = {}
	for k, v in pairs(arg_type) do
		arg[k] = symbol(v)
	end

	return terra([arg])
				return [func]([arg])
		   end
end

addtwo = emit_wrapper("addtwo", {int, int} -> {int})
setone_float = emit_wrapper("setone_float", {&matrixFloat} -> {})
setone_double = emit_wrapper("setone_double", {&matrixDouble} -> {})

local io = terralib.includec("stdio.h")
terra main()
	io.printf("Test addtwo\n")
	io.printf("%d %d %d\n", 1, 2, addtwo(1, 2))
	io.printf("Test setone_float\n")
	setone_float(nil)
	io.printf("Test setone_double\n")
	setone_double(nil)
end
main()
