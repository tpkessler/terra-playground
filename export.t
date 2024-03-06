require("export_decl")
local io = terralib.includec("stdio.h")

terra addtwo(x: int, y: int): int
	return x + y
end

local function matrix_impl(T)
	local matrixT = matrix(T)

	local terra setone(a: &matrixT)
		io.printf("Calling from type %s\n", [tostring(T)])
	end

	return setone
end

setone_float = matrix_impl(float)
setone_double = matrix_impl(double)

local export = {
	addtwo = addtwo,
	setone_float = setone_float,
	setone_double = setone_double
}

terralib.saveobj("export.o", "object", export)
