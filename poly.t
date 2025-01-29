-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local sarray = require("sarray")
local tmath = require("tmath")
local base = require("base")

local Polynomial = terralib.memoize(function(T, N)
    
    local svector = sarray.StaticVector(T,N)

    local struct poly{
        coeffs : svector
    }

    base.AbstractBase(poly)

    local _evalpoly = macro(function(self, x)
        local eval = terralib.newlist()
        local y = symbol(T)
        for i=N-2,0,-1 do
            eval:insert(quote [y] = tmath.fusedmuladd(x, [y], self.coeffs(i)) end)
        end
        local M = N-1
        return quote
            var [y] = self.coeffs.data[M]
            [eval]
        in
            [y]
        end
    end)

    poly.methods.eval = terra(self : &poly, x : T)
        return _evalpoly(self, x)
    end

    poly.metamethods.__apply = macro(function(self, x)
        return `self:eval(x)
    end)

    poly.staticmethods.from = macro(function(args)
        return `poly{svector.from([args])}
    end)

    return poly
end)

return {
    Polynomial = Polynomial
}