-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local C = terralib.includec("math.h")

local base = require("base")
local concepts = require("concepts")
local mathfun = require("mathfuns")

concepts.Complex = terralib.types.newstruct("Complex")
concepts.Base(concepts.Complex)
concepts.Complex.traits.iscomplex = true
concepts.Complex.traits.eltype = concepts.traittag

local complex = terralib.memoize(function(T, conjugated)

    local struct complex{
        re: T
        im: T
    }

    function complex.metamethods.__cast(from, to, exp)
        if to == complex then
            return `complex {exp, [T](0)}
        else
            error("Invalid scalar type of complex data type conversion")
        end
    end

    function complex.metamethods.__typename()
        return ("complex(%s)"):format(tostring(T))
    end

    -- The tostring method is cached and calling the base operation in the
    -- struct declaration already defines it.
    -- Hence we can only call it _after_ __typename is defined.  
    base.AbstractBase(complex)
    complex.traits.iscomplex = true
    complex.traits.eltype = T
    assert(concepts.Complex(complex))
    -- concepts.Complex.friends[complex] = true

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
    mathfun.real:adddefinition(terra(x: complex) return x:real() end)

    terra complex:imag()
        return self.im
    end
    mathfun.imag:adddefinition(terra(x: complex) return x:imag() end)

    terra complex:conj()
        return complex {self.re, -self.im}
    end
    mathfun.conj:adddefinition(terra(x: complex) return x:conj() end)

    if concepts.Float(T) then
        terra complex:norm(): T
            return mathfun.sqrt(self:normsq())
        end
        mathfun.abs:adddefinition(terra(x: complex) return x:norm() end)
    end

    terra complex:inverse()
       var nrmsq = self:normsq()
       return complex {self.re / nrmsq, -self.im / nrmsq}
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

    if concepts.Number(T) then
        concepts.Number.friends[complex] = true
        concepts.Complex.friends[complex] = true
    end

    if concepts.Float(T) and concepts.BLASNumber(T) then
        concepts.BLASNumber.friends[complex] = true
    end

    return complex
end)

return {
    complex = complex
}
