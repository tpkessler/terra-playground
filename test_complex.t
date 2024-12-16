-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

local concepts = require("concepts")
local complex = require("complex")
local nfloat = require("nfloat")

local float128 = nfloat.FixedFloat(128)
local i64_imag = complex.unit
local f64_imag = complex.funit

testenv "Complex numbers" do
	for _, T in pairs({float, double, float128, int8, int16, int32, int64}) do
		
		local complex = complex.complex(T)
		local im = concepts.Float(T) and f64_imag or i64_imag

		testset(T) "Initialization" do
			terracode
				var x : complex = complex.from(1, 2) 
				var y : complex = 1 + 2 * im
			end
			test x == y
		end

		testset(T) "Copy" do
			terracode
				var x : complex = 2 + 3 * im
				var y : complex = x
			end
			test x == y
		end

		testset(T) "Cast" do
			terracode
				var x : T = 2
				var y : complex = x
				var xc = complex.from(x, 0)
			end
			test y == xc
		end

		testset(T) "Add" do
			terracode
				var x : complex = 1 + 1 * im
				var y : complex = 2 + 3 * im
				var z : complex = 3 + 4 * im
			end
			test x + y == z
		end

		testset(T) "Mul" do
			terracode
				var x : complex = -1 + im
				var y : complex = 2 - 3 * im
				var z : complex = 1 + 5 * im
			end
			test x * y == z
		end

		testset(T) "Neg" do
			terracode
				var x : complex = -1 + 2 * im
				var y : complex = 1 - 2 * im
			end
			test x == -y
		end

		testset(T) "Normsq" do
			terracode
				var x : complex = 3 + 4 * im
				var y = 25
			end
			test x:normsq() == y
		end

		testset(T) "Real and imaginary parts" do
			terracode
				var x : complex = -3 + 5 * im
				var xre = -3
				var xim = 5
			end
			test x:real() == xre
			test x:imag() == xim
		end

		testset(T) "Conj" do
			terracode
				var x : complex = 5 - 3 * im
				var xc : complex = 5 + 3 * im
			end
			test x:conj() == xc
		end

		if T:isfloat() then
			testset(T) "Inverse" do
				terracode
					var x : complex = -3 + 5 * im
					var y : complex = -([T](3) / 34) - ([T](5) / 34) * im
				end
				test x:inverse() == y
			end
		end

		testset(T) "Sub" do
			terracode
				var x : complex = 2 - 3 * im
				var y : complex = 5 + 4 * im
				var z : complex = - 3 - 7 * im
			end
			test x - y == z
		end

		if T:isfloat() then
			testset(T) "Div" do
				terracode
					var x : complex = -5 + im
					var y : complex = 1 + im
					var z : complex = -2 + 3 * im
				end
				test x / y == z
			end
		end

		testset(T) "Unit" do
			terracode
				var u = complex.from(0, 1)
			end
			test u == im
		end
	end
end
