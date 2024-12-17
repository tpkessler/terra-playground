-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local base = require("base")
local concepts = require("concepts")
local mathfun = require("mathfuns")

local DualNumber = terralib.memoize(function(T)

    local struct dual{
        val: T
        tng: T
    }
    dual.eltype = T

    function dual.metamethods.__cast(from, to, exp)
        if to == dual then
            return `dual {exp, [T](0)}
        else
            error("Invalid scalar type of dual number data type conversion")
        end
    end

    function dual.metamethods.__typename()
        return ("Dual(%s)"):format(tostring(T))
    end

    -- The tostring method is cached and calling the base operation in the
    -- struct declaration already defines it.
    -- Hence we can only call it _after_ __typename is defined.  
    base.AbstractBase(dual)

    terra dual.metamethods.__add(self: dual, other: dual)
        return dual {self.val + other.val, self.tng + other.tng}
    end

    terra dual.metamethods.__mul(self: dual, other: dual)
        return dual {
            self.val * other.val,
            self.val * other.tng + self.tng * other.val
        }
    end

    terra dual.metamethods.__unm(self: dual)
        return dual {-self.val, -self.tng}
    end

    terra dual:inverse()
       return dual {1 / self.val, -self.tng / (self.val * self.val)}
    end

    terra dual.metamethods.__sub(self: dual, other: dual)
        return self + (-other)
    end

    terra dual.metamethods.__div(self: dual, other: dual)
        return self * other:inverse()
    end

    terra dual.metamethods.__eq(self: dual, other: dual)
        return self.val == other.val and self.tng == other.tng
    end

    terra dual.staticmethods.from(val: T, tng: T)
        return dual {val, tng}
    end

    concepts.Number.friends[dual] = true

    if concepts.Number(T) then
        concepts.Number:addfriend(dual)
        local fun = {}

        terra fun.exp(x: dual)
            var expval = mathfun.exp(x.val)
            return dual {expval, expval * x.tng}
        end

        terra fun.erf(x: dual)
            var y = x.val
            var erfval = mathfun.erf(y)
            var expval = 2 / mathfun.sqrt(mathfun.pi) * mathfun.exp(-y * y)
            return dual {erfval, expval * x.tng}
        end

        terra fun.sin(x: dual)
            return dual {mathfun.sin(x.val), mathfun.cos(x.val) * x.tng}
        end

        terra fun.cos(x: dual)
            return dual {mathfun.cos(x.val), -mathfun.sin(x.val) * x.tng}
        end

        terra fun.sqrt(x: dual)
            return dual {mathfun.sqrt(x.val), 1 / (2 * mathfun.sqrt(x.val)) * x.tng}
        end

        terra fun.j0(x: dual)
            return dual {mathfun.j0(x.val), -mathfun.j1(x.val) * x.tng}
        end

        terra fun.jn(n: int32, x: dual)
            if n == 0 then
                return fun.j0(x)
            else
                var val = mathfun.jn(n, x.val)
                var tng = (
                    (mathfun.jn(n - 1, x.val) - mathfun.jn(n + 1, x.val)) / 2
                    * x.tng
                )
                return dual {val, tng}
            end
        end

        terra fun.j1(x: dual)
            return fun.jn(1, x)
        end

        terra fun.abs(x: dual)
            return dual {mathfun.abs(x.val), mathfun.sign(x.val) * x.tng}
        end

        for _, lin in pairs({"real", "imag", "conj"}) do
            fun[lin] = terra(x: dual)
                return dual {[mathfun[lin]](x.val), [mathfun[lin]](x.tng)}
            end
        end

        for name, func in pairs(fun) do
            mathfun[name]:adddefinition(func)
        end

        local terra dcpow(x: T, n: int64): T
            if n < 0 then
                return dcpow(1 / x, -n)
            end
            if n == 0 then
                return [T](1)
            end
            if n == 1 then
                return x
            end
            var p2 = dcpow(x * x, n / 2)
            return terralib.select(n % 2 == 0, p2, x * p2)
        end
        for _, I in pairs({int8, int16, int32, int64}) do
            mathfun.pow:adddefinition(terra(x: dual, y: I)
                if y == 0 then
                    return [dual](1)
                else
                    return dual {
                        dcpow(x.val, y), y * dcpow(x.val, y - 1) * x.tng
                    }
                end
            end)
        end

        mathfun.pow:adddefinition(terra(x: dual, y: dual)
            var res = mathfun.pow(x.val, y.val)
            return dual {res, res * (x.tng * y.val / x.val + y.tng * mathfun.log(x.val))}
        end)
    end

    dual.metamethods.__eq = terra(x: dual, y: dual)
        return x.val == y.val and x.tng == y.tng
    end

    --[=[
        WARNING These comparison functions are only useful for measuring the
        relative distance of two dual numbers, that is |x - y|^2 < eps
        for a given tolerance eps. It uses the partial ordering implied
        by the embedding of dual numbers into the Euclidean space R^2
    --]=]
    dual.metamethods.__lt = terra(x: dual, y: dual)
        return x.val * x.val + x.tng * x.tng < y.val * y.val + y.tng * y.tng
    end

    dual.metamethods.__le = terra(x: dual, y: dual)
        return x == y or x < y
    end

    dual.metamethods.__gt = terra(x: dual, y: dual)
        return -x < -y
    end

    dual.metamethods.__ge = terra(x: dual, y: dual)
        return x == y or x > y
    end

    if concepts.Real(T) then
        concepts.Real:addfriend(dual)
    end

    if concepts.Float(T) then
        concepts.Float:addfriend(dual)
    end

    return dual
end)

return {
    DualNumber = DualNumber
}
