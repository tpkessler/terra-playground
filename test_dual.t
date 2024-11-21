-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

local dual = require("dual")
local tmath = require("mathfuns")
local io = terralib.includec("stdio.h")

local dualDouble = dual.DualNumber(double)
terra main()
    var x = dualDouble {2, 1}
    var y = tmath.sqrt(3 / x)
    io.printf("%g %g\n", y.val, y.tng)
end
main()
