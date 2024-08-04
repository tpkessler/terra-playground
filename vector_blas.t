local blas = require("blas")
local concept = require("concept")
local vecbase = require("vector_base")
local err = require("assert")

local VectorBLAS = concept.AbstractInterface:new("VectorBLAS")
VectorBLAS:inheritfrom(vecbase.Vector)
VectorBLAS:addmethod{
    getblasinfo = {} -> {concept.UInteger, &concept.BLASNumber, concept.UInteger},
}

local function VectorBLASBase(V)
    assert(VectorBLAS(V), 
        "Type " .. tostring(V) .. " does not implement the VectorBLAS interface")

    V.templates.copy[{&V.Self, &VectorBLAS} -> {}] = function(Self, X)
        local terra copy(self: Self, x: X)
            var ny, ydata, incy = self:getblasinfo()
            var nx, xdata, incx = x:getblasinfo()
            err.assert(ny == nx)
            blas.copy(ny, xdata, incx, ydata, incy)
        end
        return copy
    end

    V.templates.swap[{&V.Self, &VectorBLAS} -> {}] = function(Self, X)
        local terra swap(self: Self, x: X)
            var ny, ydata, incy = self:getblasinfo()
            var nx, xdata, incx = x:getblasinfo()
            err.assert(ny == nx)
            blas.swap(ny, xdata, incx, ydata, incy)
        end
        return swap
    end

    V.templates.scal[{&V.Self, concept.Number} -> {}] = function(Self, S)
        local terra scal(self: Self, a: S)
            var ny, ydata, incy = self:getblasinfo()
            blas.scal(ny, a, ydata, incy)
        end
        return scal
    end

    V.templates.axpy[{&V.Self, concept.Number, &VectorBLAS} -> {}] =
    function(Self, S, X)
        local terra axpy(self: Self, a: S, x: X)
            var ny, ydata, incy = self:getblasinfo()
            var nx, xdata, incx = x:getblasinfo()
            err.assert(ny == nx)
            blas.axpy(ny, a, xdata, incx, ydata, incy)
        end
        return axpy
    end

    V.templates.dot[{&V.Self, &VectorBLAS} -> concept.Number] = function(Self, X)
        local terra dot(self: Self, x: X)
            var ny, ydata, incy = self:getblasinfo()
            var nx, xdata, incx = x:getblasinfo()
            err.assert(ny == nx)
            return blas.dot(ny, xdata, incx, ydata, incy)
        end
        return swap
    end

    VectorBLAS:addimplementations{V}
end

return {
    VectorBLAS = VectorBLAS,
    VectorBLASBase = VectorBLASBase,
}
