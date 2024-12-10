-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local blas = require("blas")
local concepts = require("concepts")
local err = require("assert")

local function BLASVectorBase(Vector)

    local T = Vector.eltype
    local BLASVector = concepts.BLASVector(T)

    assert(BLASVector(Vector), 
        "Type " .. tostring(Vector) .. " does not implement the BLASVector interface")

    terraform Vector:copy(x : &X) where {X : BLASVector}
        var ny, ydata, incy = self:getblasinfo()
        var nx, xdata, incx = x:getblasinfo()
        err.assert(ny == nx)
        blas.copy(ny, xdata, incx, ydata, incy)
    end

    terraform Vector:swap(x : &X) where {X : BLASVector}
        var ny, ydata, incy = self:getblasinfo()
        var nx, xdata, incx = x:getblasinfo()
        err.assert(ny == nx)
        blas.swap(ny, xdata, incx, ydata, incy)
    end

    terraform Vector:scal(a : S) where {S : concepts.Number}
        var ny, ydata, incy = self:getblasinfo()
        blas.scal(ny, a, ydata, incy)
    end

    terraform Vector:axpy(a : S, x : &X) where {S : concepts.Number, X : BLASVector}
        var ny, ydata, incy = self:getblasinfo()
        var nx, xdata, incx = x:getblasinfo()
        err.assert(ny == nx)
        blas.axpy(ny, a, xdata, incx, ydata, incy)      
    end

    terraform Vector:dot(x : &X) where {X : BLASVector}
        var ny, ydata, incy = self:getblasinfo()
        var nx, xdata, incx = x:getblasinfo()
        err.assert(ny == nx)
        return blas.dot(ny, xdata, incx, ydata, incy)        
    end
end

return {
    BLASVectorBase = BLASVectorBase,
}
