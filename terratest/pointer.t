local C = terralib.includecstring([[
    #include <stdio.h>
]])
import "terratest"

terra set(p: &double)
    @p = 1.0
end

testenv "pointer" do
    terradef
        var x = 0.0
    end

    testset "pointer set value" do
	terradef
	    set(&x)
	end
        test x == 1.0
    end

    testset "pointer is reset in every testset" do
	test x == 0.0
    end
end
