local nfloat = require("nfloat")
local mathfun = require("mathfuns")
local io = terralib.includec("stdio.h")

local myFloat = nfloat.FixedFloat(256)
print(mathfun.log)

terra main()
    var x: myFloat = 2.0
    var y: myFloat = "3.5"
    var z = x / y
    var mypi = myFloat.pi()
    io.printf("%s\n", z:tostr())
    io.printf("%s\n", mypi:tostr())
    var sq = mathfun.log(mypi)
    io.printf("%s\n", sq:tostr())

    nfloat.clean_context()
end
main()
