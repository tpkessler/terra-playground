-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

local alloc = require("alloc")
local boltzmann = require("boltzmann")
local darray = require("darray")
local dual = require("dual")
local sarray = require("sarray")
local sparse = require("sparse")
local gauss = require("gauss")
local tmath = require("tmath")
local range = require("range")
local io = terralib.includec("stdio.h")
-- Compiled terra code, reimported for integration/unit testing
local bc = terralib.includec("./nonlinearbc.h")
local ffi = require("ffi")
if ffi.os == "Linux" then
    terralib.linklibrary("./libnonlinearbc.so")
else
    terralib.linklibrary("./libnonlinearbc.dylib")
end
--[[
for N = 2, 29 do

    testenv(N) "Half space integral aligned" do
        local Alloc = alloc.DefaultAllocator()
        local T = dual.DualNumber(double)
        local HalfSpace = boltzmann.HalfSpaceQuadrature(T)

        terracode
            var alloc: Alloc
            var rho = T {2.0 / 3.0, 3}
            var u = [sarray.StaticVector(T, 3)].from({T{-1.5, -6.75}, 0, 0})
            var theta = T {(9 + 1.0 / 6.0) / 10.0, 6.75}
            var hs = HalfSpace.new(1, 0, 0)
            var xh, wh = hs:maxwellian(&alloc, N, rho, &u, theta)
        end

        testset "Integral with constant function" do
            terracode
                var res: T = 0
                for w in wh do
                    res = res + w
                end
                var ref = T {0.039061695732712676, 0.0758567169526779}
            end

            test tmath.isapprox(res.val, ref.val, 1e-12 * ref.val)
            test tmath.isapprox(res.tng, ref.tng, 1e-12 * ref.tng)
        end

        testset "Integral with linear function" do
            terracode
                var res: T = 0
                var q = range.zip(&xh, &wh)
                for xw in q do
                    var x, w = xw
                    res = res + x._0 * w
                end
                var ref = T {0.01603974390209162, 0.0832949144360567}
            end

            test tmath.isapprox(res.val, ref.val, 1e-12 * ref.val)
            test tmath.isapprox(res.tng, ref.tng, 1e-12 * ref.tng)
        end

    end

    testenv(N) "Half space integral rotated" do
        local Alloc = alloc.DefaultAllocator()
        local T = dual.DualNumber(double)
        local HalfSpace = boltzmann.HalfSpaceQuadrature(T)

        terracode
            var alloc: Alloc
            var rho = T {2.0 / 3.0, 3}
            var u = (
                    [sarray.StaticVector(T, 3)]
                ).from({
                    T {1.5, -6.75},
                    T {0.2, 0.1},
                    T {1, 3}
                })
            var theta = T {(9 + 1.0 / 6.0) / 10.0, 6.75}
            var hs = HalfSpace.new(
                1 / tmath.sqrt(3.0), 1 / tmath.sqrt(3.0), 1 / tmath.sqrt(3.0)
            )
            var xh, wh = hs:maxwellian(&alloc, N, rho, &u, theta)

        end

        testset "Integral with constant function" do
            terracode
                var res: T = 0
                for w in wh do
                    res = res + w
                end
                var ref = T {0.6321697677872029, 2.2656508775565514}
            end

            test tmath.isapprox(res.val, ref.val, 1e-12 * ref.val)
            test tmath.isapprox(res.tng, ref.tng, 1e-12 * ref.tng)
        end

        testset "Integral with linear function" do
            local io = terralib.includec("stdio.h")
            terracode
                var res: T = 0
                var q = range.zip(&xh, &wh)
                for xw in q do
                    var x, w = xw
                    res = res + (x._0 + x._1 + x._2) * w
                end
                var ref = T {1.824036771647169, 6.332175378550762}
            end

            test tmath.isapprox(res.val, ref.val, 1e-12 * ref.val)
            test tmath.isapprox(res.tng, ref.tng, 1e-12 * ref.tng)
        end
    end

end
--]]

testenv "Full Phasespace Integral" do
    local T = double
    local I = int32
    local dMat = darray.DynamicMatrix(T)
    local iMat = darray.DynamicMatrix(I)
    local CSR = sparse.CSRMatrix(T, I)
    local Alloc = alloc.DefaultAllocator()

    terracode
        var alloc: Alloc
        var npts = 10
        var ntrialx = 3
        var xg, wg = gauss.legendre(&alloc, npts)
        var trialx = CSR.new(&alloc, npts, ntrialx)
        for i = 0, npts do
            var x = xg(i)
            trialx:set(i, 0, x)
            trialx:set(i, 1, 1 - x)
            trialx:set(i, 2, x * x)
        end
        var ntestx = 2
        var testx = CSR.new(&alloc, ntestx, npts)
        for j = 0, npts do
            var x = xg(j)
            var w = wg(j)
            testx:set(0, j, w * x)
            testx:set(1, j, w * (1 - x))
        end

        var ntrialv = 4
        var trial_powers = (
            iMat.from(
                    &alloc,
                    {
                        {0, 0, 0},
                        {3, 0, 0},
                        {0, 2, 0},
                        {0, 0, 2}
                    }
            )
        )
        var ntestv = 3
        var test_powers = (
            iMat.from(
                    &alloc,
                    {
                        {0, 0, 0},
                        {1, 0, 0},
                        {0, 1, 0}
                    }
            )
        )
        var ndim = 2
        var ref_normal = arrayof(T, 0, 1)
        var normal = dMat.new(&alloc, {npts, ndim})
        for i = 0, npts do
            for j = 0, ndim do
                normal(i, j) = ref_normal[j]
            end
        end

        var pressure = 2.5

        var resval = dMat.new(&alloc, {ntestx, ntestv})
        var restng = dMat.new(&alloc, {ntestx, ntestv})

        var val = dMat.from(
                        &alloc,
                        {
                            {1.9912029780192033,-0.45264986607769675,0.8339595275758231,-0.2028291609506634},
                            {0.5934408401820899,0.07093434833413959,0.6353261828993575,0.40155234760116665},
                            {1.194994995666661,0.46123725592209786,0.5978999738158559,0.1658215984090856}
                        }
                    )
        var tng = dMat.ones(&alloc, {3, 4})

        bc.pressurebc(
                ntestx,
                ntestv,
                --
                ntrialx,
                ntrialv,
                --
                &(val(0, 0)),
                &tng(0, 0),
                --
                npts,
                ndim,
                &normal(0, 0),
                --
                testx.data:size(),
                &testx.data(0),
                &testx.col(0),
                &testx.rowptr(0),
                --
                trialx.data:size(),
                &trialx.data(0),
                &trialx.col(0),
                &trialx.rowptr(0),
                --
                &test_powers(0, 0),
                &trial_powers(0, 0),
                --
                &resval(0, 0),
                &restng(0, 0),
                pressure
        )

        -- Values from previous runs, so it's regression test.
        -- The integral was also computed with a Mathematica implementation.
        var refval = dMat.from(
                            &alloc,
                            {
                                {0.000881819, 0.458849, -1.11022e-16},
                                {-1.75616, -1.10924, 2.5}
                            }
        )
    end
    for i = 0, 1 do
        for j = 0, 2 do
            test tmath.isapprox(resval(i, j), refval(i, j), 1e-5)
        end
    end
end
