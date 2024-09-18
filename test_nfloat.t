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

    nfloat.clean_context()
end
main()
