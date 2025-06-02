-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local blend = require("blend")
local C = terralib.includec("math.h")

import "terratest@v1/terratest"

testenv "Math functions" do
    testset "Sinc" do
        local sinc = blend.blend(
            terra(x: double) return (x == 0) end,
            terra(x: double) return 1 end,
            terra(x: double) return C.sin(x) / x end
        )
        test [terralib.isfunction(sinc) == true]
        test sinc(0) == 1
        test sinc(1e-1) == 0.9983341664682815
    end
end
