-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest@v1/terratest"

local gnuplot = require("gnuplot")



if not __silent__ then

    terra test1()

        var fig : gnuplot.handle
        gnuplot.setterm(fig, "wxt", 600, 400)
        gnuplot.plot_equation(fig, "sin(x)", "Sine wave")

    end
    test1()

end