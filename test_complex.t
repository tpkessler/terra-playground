import "terratest/terratest"

local complex = require("complex")

for _, T in pairs({float, double}) do
	local complexT, It = unpack(complex(T))
	testenv(T) "Initialization" do
		terracode
			var x = complexT {1, 2} 
			var y = 1 + 2 * It
		end
		test x == y
	end

	testenv(T) "Copy" do
		terracode
			var x = 2 + 3 * It
			var y = x
		end
		test x == y
	end

	testenv(T) "Cast" do
		terracode
			var x: T = 2
			var y: complexT = x
			var xc = complexT {x, 0}
		end
		test y == xc
	end

	testenv(T) "Add" do
		terracode
			var x = 1 + 1 * It
			var y = 2 + 3 * It
			var z = 3 + 4 * It
		end
		test x + y == z
	end

	testenv(T) "Mul" do
		terracode
			var x = -1 + It
			var y = 2 - 3 * It
			var z = 1 + 5 * It
		end
		test x * y == z
	end

	testenv(T) "Neg" do
		terracode
			var x = -1 + 2 * It
			var y = 1 - 2 * It
		end
		test x == -y
	end

	testenv(T) "Normsq" do
		terracode
			var x = 3 + 4 * It
			var y = 25
		end
		test x:normsq() == y
	end

	testenv(T) "Real and imaginary parts" do
		terracode
			var x = -3 + 5 * It
			var xre = -3
			var xim = 5
		end
		test x:real() == xre
		test x:imag() == xim
	end

	testenv(T) "Conj" do
		terracode
			var x = 5 - 3 * It
			var xc = 5 + 3 * It
		end
		test x:conj() == xc
	end

	testenv(T) "Inverse" do
		terracode
			var x = -3 + 5 * It
			var y = -[T](3) / 34 - [T](5) / 34 * It
		end
		test x:inverse() == y
	end

	testenv(T) "Sub" do
		terracode
			var x = 2 - 3 * It
			var y = 5 + 4 * It
			var z = - 3 - 7 * It
		end
		test x - y == z
	end

	testenv(T) "Div" do
		terracode
			var x = -5 + It
			var y = 1 + It
			var z = -2 + 3 * It
		end
		test x / y == z
	end

	testenv(T) "Unit" do
		terracode
			var u = complexT {0, 1}
		end
		test u == It
	end
end
