-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

local C = terralib.includec("string.h")
local tmath = require("mathfuns")
local concepts = require("concepts")
local complex = require("complex")
local nfloat = require("nfloat")

local float256 = nfloat.FixedFloat(256)


testenv "Complex numbers" do
	for _, T in pairs({float, double, float256, int8, int16, int32, int64}) do
		
		local complex_t = complex.complex(T)
		local im = complex_t:unit()

		testset(T) "Initialization" do
			terracode
				var x = complex_t.from(1, 2) 
				var y = 1 + 2 * im
			end
			test x == y
		end

		testset(T) "printing" do
			local format = tmath.numtostr.format[T]
			if concepts.Float(T) then
				terracode
					format = "%0.1f"
					var s1 = tmath.numtostr(complex_t.from(1, 2))
					var s2 = tmath.numtostr(complex_t.from(1, -2))
				end
				test C.strcmp(&s1[0], "1.0+2.0im") == 0
				test C.strcmp(&s2[0], "1.0-2.0im") == 0
			elseif concepts.Integral(T) then
				terracode
					format = "%d"
					var s1 = tmath.numtostr(complex_t.from(1, 2))
					var s2 = tmath.numtostr(complex_t.from(1, -2))
				end
				test C.strcmp(&s1[0], "1+2im") == 0
				test C.strcmp(&s2[0], "1-2im") == 0
			end
        end

		testset(T) "Copy" do
			terracode
				var x = 2 + 3 * im
				var y = x
			end
			test x == y
		end

		testset(T) "Cast" do
			terracode
				var x: T = 2
				var y: complex_t = x
				var xc = complex_t.from(x, 0)
			end
			test y == xc
		end

		testset(T) "Add" do
			terracode
				var x = 1 + 1 * im
				var y = 2 + 3 * im
				var z = 3 + 4 * im
			end
			test x + y == z
		end

		testset(T) "Mul" do
			terracode
				var x = -1 + im
				var y = 2 - 3 * im
				var z = 1 + 5 * im
			end
			test x * y == z
		end

		testset(T) "Neg" do
			terracode
				var x = -1 + 2 * im
				var y = 1 - 2 * im
			end
			test x == -y
		end

		testset(T) "Normsq" do
			terracode
				var x = 3 + 4 * im
				var y = 25
			end
			test x:normsq() == y
		end

		testset(T) "Real and imaginary parts" do
			terracode
				var x = -3 + 5 * im
				var xre = -3
				var xim = 5
			end
			test x:real() == xre
			test x:imag() == xim
		end

		testset(T) "Conj" do
			terracode
				var x = 5 - 3 * im
				var xc = 5 + 3 * im
			end
			test x:conj() == xc
		end

		if T:isfloat() then
			testset(T) "Inverse" do
				terracode
					var x = -3 + 5 * im
					var y = -[T](3) / 34 - [T](5) / 34 * im
				end
				test x:inverse() == y
			end
		end

		testset(T) "Sub" do
			terracode
				var x = 2 - 3 * im
				var y = 5 + 4 * im
				var z = - 3 - 7 * im
			end
			test x - y == z
		end

		if T:isfloat() then
			testset(T) "Div" do
				terracode
					var x = -5 + im
					var y = 1 + im
					var z = -2 + 3 * im
				end
				test x / y == z
			end
		end

		testset(T) "Unit" do
			terracode
				var u = complex_t.from(0, 1)
			end
			test u == im
			test u == [complex_t:unit()]
		end
	end
end
