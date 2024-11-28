-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local tree = require("tree")
local alloc = require("alloc")
local io = terralib.includec("stdio.h")

local DefaultAllocator = alloc.DefaultAllocator()
local TreeDouble = tree.Tree(double)

import "terratest/terratest"


if not __silent__ then

    terra main()
        var alloc: DefaultAllocator
        var t = TreeDouble.new(&alloc, 0.0, 4)
        for i = 0, 4 do
            t.son(i) = TreeDouble.new(&alloc, i + 1, 0)
        end

        for x in t do
            io.printf("%g\n", x)
        end
    end
    main()

end
