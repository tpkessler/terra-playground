-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local C = terralib.includecstring[[
    #include <stdio.h>
]]
local mem = require("mem")

terra main()
    escape
        local array_len = math.pow(10, 9)
        for _, T in ipairs({rawstring, int, double, float, int64, uint32, int8}) do
            print("Generating code for type "..tostring(T))
            emit quote
                C.printf("Running C/terra now for type %s\n", [tostring(T)])
                var ptr = [&T](mem.new(sizeof(T) * [array_len]))
                for i: uint64 = 0, [array_len] do
                    @(ptr + i) = T(i)
                end
                mem.del(ptr)
            end
        end
        print("DONE with code generation")
    end
end

main()
