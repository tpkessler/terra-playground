-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"
import "terraform"

local base = require("base")
local interface = require("interface")
local concepts = require("concepts")

testenv "Simple interface" do
	local A = interface.newinterface("A")
	terra A:add(x: int, y: double): float end
	A:complete()

	testset "No methods" do
		local struct a
		local ok, ret = pcall(function(A, a) return A:isimplemented(a) end, A, a)

		test [ok == false]
	end

	testset "Wrong input type" do
		local struct b
		terra b:add(x: int, y: float): float end
		local ok, ret = pcall(function(A, a) return A:isimplemented(a) end, A, b)

		test [ok == false]
	end

	testset "Wrong return type" do
		local struct c
		terra c:add(x: int, y: double): double end
		local ok, ret = pcall(function(A, a) return A:isimplemented(a) end, A, c)

		test [ok == false]
	end

	testset "Full implementation" do
		local struct d
		terra d:add(x: int, y: double): float end
		local ok, ret = (pcall(function(A, a) return A:isimplemented(a) end, A, d))

		test [ok == true]
	end

	testset "Cast" do
		local terra eval(a: A, y: double)
			return a:add(2, y)
		end

		local struct S {}
		terra S:add(x: int, y: double): float
			return x + y
		end

		terracode
			var s: S
		end

		test eval(&s, 3.14) == 5.14f
	end
end

testenv "Multiple methods" do
	local B = interface.newinterface("B")
	terra B:add_one() end
	terra B:inc(x: int): double end
	B:complete()

	local struct S {
		x: double
		y: int
	}
	terra S:add_one() self.x = self.x + 1.0 end
	terra S:inc(y: int) self.y = self.y + y; return 1.0 end

	testset "Implemented" do
		local ok, ret = pcall(function(T) return B:isimplemented(T) end, S)
		test ok == true
	end

	testset "Cast" do
		terracode
			var s = S {2.0, 3}
			var a: B = &s
			a:add_one()
			var rs = a:inc(2)
			var xs = s.x
			var ys = s.y
		end
		test rs == 1.0
		test xs == 3.0
		test ys == 5
	end
end

testenv "Template methods" do
	local C = interface.newinterface("C")
	terra C:inc(x: int): double end
	C:complete()

	local struct foo {}
	base.AbstractBase(foo)

	local Integer = concepts.Integer
	terraform foo:inc(x: I) where {I: Integer}
		return x + 2.71
	end

	testset "Implemented" do
		local ok, ret = pcall(function(T) return C:isimplemented(T) end, foo)
		test ok == true
	end

	testset "Cast" do
		terracode
			var s: foo
			var c: C = &s
			var r = c:inc(2)
		end
		test r == 4.71
	end
end
