import "terraform"
local io = terralib.includec("stdio.h")
local lambda = require("lambda")

local size_t = uint64

local struct integrant{
    x : double
    y : double
}

terraform integrant:eval(kernel : K, npts : size_t) where {K}
    return kernel(self.x) * npts
end


local Kernel = lambda.lambda(double -> double, struct {y: double})

terra main()
    --define lambda
    var kernel = Kernel.new([terra(x : double, y : double) return x * y end], 2.0)
    --io.printf("kernel(...) = %0.2f\n", kernel(10.0))
    --integrant
    var x = integrant{2.,3.}
    io.printf("x:eval(...) = %0.2f\n", x:eval(kernel, 10))
end
main()
