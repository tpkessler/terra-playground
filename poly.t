local vec = require("svector")
local mathfuns = require("mathfuns")

local Polynomial = terralib.memoize(function(T, N)
    
    local svector = vec.StaticVector(T,N)

    local struct poly(Base){
        coeffs : svector
    }

    poly.staticmethods = {}

    poly.metamethods.__getmethod = function(self, methodname)
        return self.methods[methodname] or poly.staticmethods[methodname]
    end

    local _evalpoly = macro(function(self, x)
        local eval = terralib.newlist()
        local y = symbol(T)
        for i=N-2,0,-1 do
            eval:insert(quote [y] = mathfuns.fusedmuladd(x, [y], self.coeffs(i)) end)
        end
        local M = N-1
        return quote
            var [y] = self.coeffs.data[M]
            [eval]
        in
            [y]
        end
    end)

    poly.methods.eval = terra(self : &poly, x : T)
        return _evalpoly(self, x)
    end


    poly.metamethods.__apply = macro(function(self, x)
        return `self:eval(x)
    end)

    poly.staticmethods.from = macro(function(...)
        local args = {...}
        return `poly{svector.from(args)}
    end)

    return poly
end)

return {
    Polynomial = Polynomial
}