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

local prod = {}

terra prod.reduce_1d(w : &tuple(double))
    return w._0
end

terra prod.reduce_2d(w : &tuple(double, double))
    return w._0 * w._1
end

terra prod.reduce_3d(w : &tuple(double, double, double))
    return w._0 * w._1 * w._2
end


local tprule = terralib.types.newstruct("tprule")
tprule:setconvertible("tuple")
--entry lookup quadrature points and weights
tprule.metamethods.__entrymissing = macro(function(entryname, self)
    if entryname=="x" then
        return `self._0
    end
    if entryname=="w" then
        return `self._1
    end
end)

local productrule = macro(function(...)
    local args = terralib.newlist{...}
    local D = #args
    local xargs, wargs = terralib.newlist(), terralib.newlist()
    for k,v in pairs(args) do
        local tp = v.tree.type
        local x, w = tp.entries[1], tp.entries[2]
        assert(x.type.isrange and w.type.isrange)
    end
    for i,qr in ipairs(args) do
        xargs:insert(quote in &qr.x end)
        wargs:insert(quote in &qr.w end)
    end
    --get reduction method
    local reduction = prod["reduce_" ..tostring(D) .."d"]
    --return quadrature rule
    return quote
        var x = rn.product([xargs])
        var w = rn.product([wargs]) >> rn.transform([reduction])
        escape
            tprule.entries:insert({field = "_0", type = x.type})
            tprule.entries:insert({field = "_1", type = w.type})
            tprule:complete()
        end
    in
        tprule{x, w}
    end
end)

local terra main()
    var alloc : DefaultAllocator
    var Q_1 = gauss.rule("legendre", &alloc, 3)
    var Q_2 = gauss.rule("legendre", &alloc, 4)

    var rule = productrule(Q_1, Q_2)

    for qr in rn.zip(rule.x, rule.w) do
        var xx, ww = qr
        io.printf("x, w = (%0.2f, %0.2f), (%0.2f)\n", xx._0, xx._1, ww)
    end
end
main()