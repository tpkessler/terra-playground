-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local io = terralib.includec('stdio.h')
local alloc = require('alloc')
local gauss = require("gauss")
local rn = require("range")

local Allocator = alloc.Allocator
local DefaultAllocator =  alloc.DefaultAllocator()

local T = double
local N = 10

local terra main()
    var alloc : DefaultAllocator
    var x1, w1 = gauss.legendre(&alloc, N)
    var x2, w2 = gauss.legendre(&alloc, N)

    io.printf("all good here\n")

    for qr in rn.zip(rn.product(&x1, &x2), rn.product(&w1, &w2) >> rn.transform([terra(w : &tuple(T,T)) return w._0 * w._1 end])) do
        var x, w = qr._0, qr._1
        io.printf("x, w = (%0.2f, %0.2f), (%0.2f)\n", x._0, x._1, w)
    end
end
main()