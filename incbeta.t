-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

-- Regularized Incomplete Beta Function
-- according to the C - implementaiton at https://github.com/codeplea/incbeta

local math = require("mathfuns")

local STOP = 1.0e-8
local TINY = 1.0e-30

local terra incbeta(a : double, b : double, x : double) : double
    if (x < 0 or x > 1) then return 1.0/0.0 end
    --The continued fraction converges nicely for x < (a+1)/(a+b+2)
    --Use the fact that beta is symmetrical.*/
    if (x > (a+1.0) / (a+b+2.0)) then 
        return 1.0-incbeta(b,a,1.0-x) 
    end
    --Find the first part before the continued fraction.
    var lbeta_ab : double = math.loggamma(a) + math.loggamma(b) - math.loggamma(a+b)
    var front : double = math.exp( math.log(x)*a + math.log(1.0-x)*b - lbeta_ab) / a
    --Use Lentz's algorithm to evaluate the continued fraction.
    var f, c, d = 1.0, 1.0, 0.0
    var m : int
    for i = 0, 200 do
        m = i/2
        --first compute the numerator
        var numerator : double
        if i==0 then
            numerator = 1.0    --first numerator is 1.0
        elseif i % 2 == 0 then
            numerator = (m*(b-m)*x) / ((a+2.0*m-1.0) * (a+2.0*m)) --even term
        else
            numerator = -((a+m) * (a+b+m)*x) / ((a+2.0*m) * (a+2.0*m+1)) --odd term
        end
        --do an iteration of Lentz's algorithm
        d = 1.0 + numerator * d
        if (math.abs(d) < TINY) then d = TINY end
        d = 1.0 / d

        c = 1.0 + numerator / c
        if (math.abs(c) < TINY) then c = TINY end

        var cd = c * d
        f = f * cd;

        --check for stop
        if (math.abs(1.0-cd) < STOP) then
            return front * (f-1.0);
        end
    end
    return 1.0/0.0 --Needed more loops, did not converge
end

return incbeta