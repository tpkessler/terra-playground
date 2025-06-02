-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local base = require("base")
local range = require("range")
local momfit = require("momfit")
local tmath = require("tmath")

import "terratest@v1/terratest"

local tols = {
    [float] = `1e-6f,
    [double] = `1e-15,
}

for T, tol in pairs(tols) do
    testenv(T) "Clenshaw-Curtis with constant weight" do
        local Interval = momfit.IntervalFactory(T)
        local ConstMom = momfit.ConstMom(T)
        local DefaultAlloc = alloc.DefaultAllocator()
        local io = terralib.includec("stdio.h")
        for N = 1, 30 do
            testset(N) "Order" do
                terracode
                    var alloc: DefaultAlloc
                    var refdom = Interval.new(-1, 1)
                    var rec: ConstMom
                    var xq, wq = momfit.clenshawcurtis(&alloc, N, &rec, &refdom)
                    var res: T = 0
                    for xw in range.zip(&xq, &wq) do
                        var x, w = xw
                        res = res + w * x * x
                    end
                    var ref = [T](2) / 3
                end
                test tmath.isapprox(wq:sum(), 2, 2 * tol)
                if N > 2 then
                    test tmath.isapprox(res, ref, ref * tol)
                end
            end
        end
    end
end
