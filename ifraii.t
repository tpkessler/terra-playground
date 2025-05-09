-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local io = terralib.includec("stdio.h")
require("terralibext")

local a = global(int, 0)
local struct A {}

terra A:__init()
    a = 0
    io.printf("Calling __init with value of a = %d\n", a)
end

terra A.methods.__copy(from: &int, to: &A)
    a = @from
    io.printf("Calling __copy with value of a = %d\n", a)
end

terra A:__dtor()
    io.printf("Calling __dtor with value of a = %d\n", a)
end

terra test(b: bool)
    var a: A
    if b then
        a = 7
        -- return 0
    else
        a = -7
        -- return 0
    end
end

test(true)
test(false)
