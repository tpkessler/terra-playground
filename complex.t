-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local C = terralib.includecstring[[
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <math.h>
]]

import "terraform"

local base = require("base")
local concepts = require("concepts")
local tmath = require("mathfuns")

concepts.Complex = terralib.types.newstruct("Complex")
concepts.Base(concepts.Complex)
concepts.Complex.traits.iscomplex = true
concepts.Complex.traits.eltype = concepts.traittag


local complex = terralib.memoize(function(T)

    local struct complex{
        re: T
        im: T
    }

    function complex.metamethods.__cast(from, to, exp)
        if to == complex then
            if concepts.Real(from) then
                return `complex {exp, [T](0)}
            elseif concepts.Complex(from) then
                return `complex{exp.re, exp.im}
            end
        end
        error("Invalid conversion from " .. tostring(from) .. "to type " ..  tostring(to) .. ".")
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
    tmath.real:adddefinition(terra(x: complex) return x:real() end)

    terra complex:imag()
        return self.im
    end
    tmath.imag:adddefinition(terra(x: complex) return x:imag() end)

    terra complex:conj()
        return complex {self.re, -self.im}
    end
    tmath.conj:adddefinition(terra(x: complex) return x:conj() end)

    if concepts.Float(T) then
        terra complex:norm(): T
            return tmath.sqrt(self:normsq())
        end
        tmath.abs:adddefinition(terra(x: complex) return x:norm() end)
    end

    --maxlen is twice the size of T and twice one char for the sign
    local maxlen = 2 * tmath.ndigits(sizeof(T)) + 2
    terra complex:tostr()
        var buffer : int8[maxlen]
        var re, im =  self:real(), self:imag()
        if im < 0 then
            im = -im
            var s1, s2 = tmath.numtostr(re), tmath.numtostr(im)
            var j = C.snprintf(buffer, maxlen, "%s-%sim", s1, s2)
        else
            var s1, s2 = tmath.numtostr(re), tmath.numtostr(im)
            var j = C.snprintf(buffer, maxlen, "%s+%sim", s1, s2)
        end
        return buffer
    end

    tmath.numtostr:adddefinition(
        terra(x : complex) 
            return x:tostr() 
        end
    )

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
    
    terra complex.metamethods.__ne(self: complex, other: complex)
        return self:real() ~= other:real() or self:imag() ~= other:imag()
    end

    terra complex.staticmethods.from(x: T, y: T)
        return complex {x , y}
    end

    if concepts.Primitive(T) then
        function complex:zero()
            return constant(complex, `complex{0, 0})
        end
        function complex:unit()
            return constant(complex, `complex{0, 1})
        end
    elseif concepts.NFloat(T) then
        function complex:zero()
            return constant(terralib.new(complex, {T:__newzero(), T:__newzero()}))
        end
        function complex:unit()
            return constant(terralib.new(complex, {T:__newzero(), T:__newunit()}))
        end
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
