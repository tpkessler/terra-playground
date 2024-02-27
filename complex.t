local sqrt = terralib.overloadedfunction("sqrt")
for tname, ttype in pairs{f32 = float, f64 = double} do
    local d = terra(x: ttype) return [
        terralib.intrinsic("llvm.sqrt."..tname, ttype -> ttype)](x)
    end
    sqrt:adddefinition(d)
end

local function complex(T)

    local struct complex{
        re: T
        im: T
    }
    complex:setconvertible("array")

    complex.scalar_type = T

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

    terra complex:normsq(): T
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

    if T == double or T == float then
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

    local I = `complex {0, 1}
    return {complex, I}
end

local complex = terralib.memoize(complex)

return complex
