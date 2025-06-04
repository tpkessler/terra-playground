-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest@v1/terratest"

local poly = require('poly')
local io = terralib.includec("stdio.h")



testenv "Static polynomial" do

    local polynomial = poly.Polynomial(double, 4)
    
    testset "eval" do
        terracode
            var p = polynomial.from({-1,2,-6,2})
        end
        test p(3)==5
    end

end