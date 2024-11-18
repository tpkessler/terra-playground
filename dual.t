-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local base = require("base")
local concept = require("concept-new")
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

    concept.Number.friends[dual] = true

    if concept.Real(T) then
        concept.Real.friends[dual] = true
        local fun = {}

        terra fun.exp(x: dual)
            var expval = mathfun.exp(x.val)
            return dual {expval, expval * x.tng}
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

        for name, func in pairs(fun) do
            mathfun[name]:adddefinition(func)
        end
    end

    return dual
end)

return {
    DualNumber = DualNumber
}
