import "terratest/terratest"

local poly = require('poly')
local io = terralib.includec("stdio.h")



testenv "Static polynomial" do

    local polynomial = poly.Polynomial(double, 4)
    
    testset "eval" do
        terracode
            var p = polynomial.from(-1,2,-6,2)
        end
        test p(3)==5
    end

end