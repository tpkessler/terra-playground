-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

require("export_decl")
local io = terralib.includec("stdio.h")
local lib = terralib.includec("stdlib.h")

terra addtwo(x: int, y: int): int
	return x + y
end

local function matrix(T)
	return struct{
		a: T
	}
end

local function matrix_impl(T)
	local matrixT = matrix(T)

	terra matrixT:setone()
		io.printf("Calling from type %s with value %g\n", [tostring(T)], self.a)
	end

	local terra new(a: T)
		var ret = [&matrixT](lib.malloc(sizeof(matrixT)))
		ret.a = a
		return ret
	end

	local terra del(m: &matrixT)
		lib.free(m)
	end

	local self = {type = matrixT, new = new, del = del}

	return self
end

mat_float = matrix_impl(float)
mat_double = matrix_impl(double)

local export = {
	addtwo = addtwo,
	-- float
	new_float = mat_float.new,
	del_float = mat_float.del,
	setone_float = mat_float.type.methods["setone"],
	-- double
	new_double = mat_double.new,
	del_double = mat_double.del,
	setone_double = mat_double.type.methods["setone"]
}

terralib.saveobj("export.o", "object", export)
