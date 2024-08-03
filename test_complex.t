import "terratest/terratest"

local complex = require("complex")

testenv "Complex numbers" do
	for _, T in pairs({float, double, int8, int16, int32, int64}) do
		local complex = complex.complex(T)
		testset(T) "Initialization" do
			terracode
				var x = complex.from(1, 2) 
				var y = 1 + 2 * complex.I()
			end
			test x == y
		end

		testset(T) "Copy" do
			terracode
				var x = 2 + 3 * complex.I()
				var y = x
			end
			test x == y
		end

		testset(T) "Cast" do
			terracode
				var x: T = 2
				var y: complex = x
				var xc = complex.from(x, 0)
			end
			test y == xc
		end

		testset(T) "Add" do
			terracode
				var x = 1 + 1 * complex.I()
				var y = 2 + 3 * complex.I()
				var z = 3 + 4 * complex.I()
			end
			test x + y == z
		end

		testset(T) "Mul" do
			terracode
				var x = -1 + complex.I()
				var y = 2 - 3 * complex.I()
				var z = 1 + 5 * complex.I()
			end
			test x * y == z
		end

		testset(T) "Neg" do
			terracode
				var x = -1 + 2 * complex.I()
				var y = 1 - 2 * complex.I()
			end
			test x == -y
		end

		testset(T) "Normsq" do
			terracode
				var x = 3 + 4 * complex.I()
				var y = 25
			end
			test x:normsq() == y
		end

		testset(T) "Real and imaginary parts" do
			terracode
				var x = -3 + 5 * complex.I()
				var xre = -3
				var xim = 5
			end
			test x:real() == xre
			test x:imag() == xim
		end

		testset(T) "Conj" do
			terracode
				var x = 5 - 3 * complex.I()
				var xc = 5 + 3 * complex.I()
			end
			test x:conj() == xc
		end

		if T:isfloat() then
			testset(T) "Inverse" do
				terracode
					var x = -3 + 5 * complex.I()
					var y = -[T](3) / 34 - [T](5) / 34 * complex.I()
				end
				test x:inverse() == y
			end
		end

		testset(T) "Sub" do
			terracode
				var x = 2 - 3 * complex.I()
				var y = 5 + 4 * complex.I()
				var z = - 3 - 7 * complex.I()
			end
			test x - y == z
		end

		if T:isfloat() then
			testset(T) "Div" do
				terracode
					var x = -5 + complex.I()
					var y = 1 + complex.I()
					var z = -2 + 3 * complex.I()
				end
				test x / y == z
			end
		end

		testset(T) "Unit" do
			terracode
				var u = complex.from(0, 1)
			end
			test u == complex.I()
			test u == complex.unit()
		end
	end
end
