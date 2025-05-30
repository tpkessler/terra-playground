-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest"

local base = require("base")

testenv "New Base" do
	local Foo = base.Base:new("Foo", function(T) error("Catch me if you can!") end)
	local ok, ret = pcall(Foo, int)
	local i,j = ret:find("Catch me if you can!")
	
	test ok == false
	test i > 0
	test j > 0
end

testenv "Multiple Base" do
	local counter = 1
	local Foo = base.Base:new("Foo", function(T) counter = counter + 3 end)
	local Bar = base.Base:new("Bar", function(T) counter = 2 * counter end)
	local FooBar = Foo * Bar
	FooBar()
	terracode
		var res1 = counter
	end
	counter = 1
	local BarFoo = Bar * Foo
	BarFoo()
	terracode
		var res2 = counter
	end

	testset "Ordering" do
		test res1 == 8
		test res2 == 5
	end
end

testenv "Operation on terra structs" do
	local B = base.Base:new("B", function(T)
		terra T:inc()
			self.a = self.a + 1
		end
	end)
	local struct A(B){
		a: int
	}
	terracode
		var a = A {2}
	end

	testset "Initial state" do
		test a.a == 2
	end

	testset "Call to base methods" do
		terracode
			a:inc()
		end
		test a.a == 3
	end
end
