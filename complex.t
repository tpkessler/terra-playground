local C = terralib.includec("math.h")
local sqrt = terralib.overloadedfunction("sqrt", {C.sqrt, C.sqrtf})

local base = require("base")
local concept = require("concept")

local complex = terralib.memoize(function(T)

    local struct complex(base.AbstractBase){
        re: T
        im: T
    }
    complex:setconvertible("array")

    complex.eltype = T

    function complex.metamethods.__cast(from, to, exp)
        if to == complex then
            return `complex {exp, [T](0)}
        else
            error("Invalid scalar type of complex data type conversion")
        end
    end

    function complex.metamethods.__typename()
        return string.format("complex(%s)", tostring(T))
    end

    terra complex.metamethods.__add(self: complex, other: complex)
        return complex {self.re + other.re, self.im + other.im}
    end

    terra complex.metamethods.__mul(self: complex, other: complex)
        return complex {self.re * other.re - self.im * other.im,
                        self.re * other.im + self.im * other.re}
    end

    terra complex.metamethods.__unm(self: complex)
        return complex {-self.re, -self.im}
    end

    terra complex:normsq()
        return self.re * self.re + self.im * self.im
    end

    terra complex:real()
        return self.re
    end

    terra complex:imag()
        return self.im
    end

    terra complex:conj()
        return complex {self.re, -self.im}
    end

    if T:isfloat() then
        terra complex:norm(): T
            return sqrt(self:normsq())
        end
    end

    terra complex:inverse()
       var nrmsq = self:normsq()
       return {self.re / nrmsq, -self.im / nrmsq}
    end

    terra complex.metamethods.__sub(self: complex, other: complex)
        return self + (-other)
    end

    terra complex.metamethods.__div(self: complex, other: complex)
        return self * other:inverse()
    end

    terra complex.metamethods.__eq(self: complex, other: complex)
        return self:real() == other:real() and self:imag() == other:imag()
    end

    terra complex.staticmethods.from(x: T, y: T)
        return complex {x , y}
    end
    
    local I = `complex.from(0, 1)
    for _, name in pairs({"I", "unit"}) do
        complex.staticmethods[name] = terra() return complex.from(0, 1) end
        complex.staticmethods[name]:setinlined(true)
    end

    if concept.Number(T) then
        concept.Number:addimplementations{complex}
        concept.Complex:addimplementations{complex}
    end

    if concept.BLASNumber(T) then
        concept.BLASNumber:addimplementations{complex}
    end

    return complex
end)

return {
    complex = complex
}
