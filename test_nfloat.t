-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local nfloat = require("nfloat")
local mathfun = require("mathfuns")
local io = terralib.includec("stdio.h")

local myFloat = nfloat.FixedFloat(256)
print(mathfun.log)
print(myFloat.metamethods.__eq)

if not __silent__ then

    terra main()
        var x: myFloat = 2.0
        var y: myFloat = "3.5"
        var z = x / y
        var mypi = myFloat.pi()
        io.printf("%s\n", z:tostr())
        io.printf("%s\n", mypi:tostr())
        var sq = mathfun.log(mypi)
        io.printf("%s\n", sq:tostr())
        io.printf("Are x and y equal? %s\n", terralib.select(x == y, "True", "False"))
        io.printf("Is x smaller than y? %s\n", terralib.select(x < y, "True", "False"))
        io.printf("Is x greater than y? %s\n", terralib.select(x > y, "True", "False"))
        
        --taking the modulus
        var z2 = y % 2
        io.printf("%s = %s mod %d\n", z2:tostr(), y:tostr(), 2)

        --truncating to a double
        var y2 : myFloat = myFloat.pi()
        var x2 = y2:truncatetodouble()
        io.printf("y = %s\n", y2:tostr())
        io.printf("x = %0.16f\n", x2)
        nfloat.clean_context()
    end
    main()


end