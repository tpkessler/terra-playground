import "terratest/terratest"

local Alloc = require("alloc")["Default"]


testenv "Default allocator" do
	terracode
		var A: Alloc
		var x: &double = nil
	end

	testset "Init" do
		test x == nil
	end

	testset "Alloc" do
		terracode
			x = [&double](A:alloc(sizeof(double)))
		end
		test x ~= nil
	end

	testset "Free" do
		terracode
			A:free(x)
		end
	end
end

terra main()
	var A: Alloc
	var x: &double = [&double](A:alloc(10 * sizeof(double)))
	A:free(x)
end
main()
