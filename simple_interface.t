-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local io = terralib.includec("stdio.h")
local interface = require "interface"

local I = interface.Interface:new{
	size = {} -> int64,
	get = int64 -> double,
	set = {int64, double} -> {}
}

local struct A {}
terra A:size(): int64 return 1 end
terra A:get(i: int64) return 1.3 end
terra A:set(i: int64, a: double) end

local struct B {}
terra B:size(): int64 return 2 end
terra B:get(i: int64) return -0.33 end
terra B:set(i: int64, a: double) end

terra foo(a: I)
	return 2 * a:get(0)
end

local io = terralib.includec("stdio.h")
terra main()
	var a: A
	var b: B

	io.printf("for A it's %g %g\n", foo(&a), foo(&a))
	io.printf("for B it's %g %g\n", foo(&b), foo(&b))
end

main()
