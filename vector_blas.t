-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local blas = require("blas")
local concepts = require("concepts")
local err = require("assert")

local Integral = concepts.Integral
local BLASNumber = concepts.BLASNumber


local function BLASVectorBase(V)

    local T = V.eltype
    local BLASVector = concepts.BLASVector(T)
    local Number = concepts.Number

    assert(BLASVector(V), 
        "Type " .. tostring(V) .. " does not implement the BLASVector interface")

    terraform V:copy(x : &X) where {X : BLASVector}
        var ny, ydata, incy = self:getblasinfo()
        var nx, xdata, incx = x:getblasinfo()
        err.assert(ny == nx)
        blas.copy(ny, xdata, incx, ydata, incy)
    end

    terraform V:swap(x : &X) where {X : BLASVector}
        var ny, ydata, incy = self:getblasinfo()
        var nx, xdata, incx = x:getblasinfo()
        err.assert(ny == nx)
        blas.swap(ny, xdata, incx, ydata, incy)
    end

    terraform V:scal(a : S) where {S : Number}
        var ny, ydata, incy = self:getblasinfo()
        blas.scal(ny, a, ydata, incy)
    end

    terraform V:axpy(a : S, x : &X) where {S : Number, X : BLASVector}
        var ny, ydata, incy = self:getblasinfo()
        var nx, xdata, incx = x:getblasinfo()
        err.assert(ny == nx)
        blas.axpy(ny, a, xdata, incx, ydata, incy)      
    end

    terraform V:dot(x : &X) where {X : BLASVector}
        var ny, ydata, incy = self:getblasinfo()
        var nx, xdata, incx = x:getblasinfo()
        err.assert(ny == nx)
        return blas.dot(ny, xdata, incx, ydata, incy)        
    end
end

return {
    BLASVectorBase = BLASVectorBase
}
