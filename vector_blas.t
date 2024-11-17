-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT
import "terraform"
local blas = require("blas")
local concept = require("concept-new")
local veccont = require("vector_contiguous")
local err = require("assert")

local struct VectorBLAS(concept.Base) {}
VectorBLAS:inherit(veccont.VectorContiguous)
local Integral = concept.Integral
local BLASNumber = concept.BLASNumber
VectorBLAS.methods.getblasinfo = {&VectorBLAS} -> {Integral, BLASNumber, Integral}

local function VectorBLASBase(V)
    assert(VectorBLAS(V), 
        "Type " .. tostring(V) .. " does not implement the VectorBLAS interface")

    terraform V:copy(x : &X) where {X : VectorBLAS}
        var ny, ydata, incy = self:getblasinfo()
        var nx, xdata, incx = x:getblasinfo()
        err.assert(ny == nx)
        blas.copy(ny, xdata, incx, ydata, incy)
    end

    terraform V:swap(x : &X) where {X : VectorBLAS}
        var ny, ydata, incy = self:getblasinfo()
        var nx, xdata, incx = x:getblasinfo()
        err.assert(ny == nx)
        blas.swap(ny, xdata, incx, ydata, incy)
    end

    terraform V:scal(a : S) where {S : concept.Number}
        var ny, ydata, incy = self:getblasinfo()
        blas.scal(ny, a, ydata, incy)
    end

    terraform V:axpy(a : S, x : &X) where {S : concept.Number, X : VectorBLAS}
        var ny, ydata, incy = self:getblasinfo()
        var nx, xdata, incx = x:getblasinfo()
        err.assert(ny == nx)
        blas.axpy(ny, a, xdata, incx, ydata, incy)      
    end

    terraform V:dot(x : &X) where {X : VectorBLAS}
        var ny, ydata, incy = self:getblasinfo()
        var nx, xdata, incx = x:getblasinfo()
        err.assert(ny == nx)
        return blas.dot(ny, xdata, incx, ydata, incy)        
    end
end

return {
    VectorBLAS = VectorBLAS,
    VectorBLASBase = VectorBLASBase,
}
