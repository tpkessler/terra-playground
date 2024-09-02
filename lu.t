local factorization = require("factorization")
local base = require("base")
local err = require("assert")
local concept = require("concept")
local template = require("template")
local matbase = require("matrix")
local vecbase = require("vector")
local mathfun = require("mathfuns")

local LUFactory = terralib.memoize(function(M, P)
    assert(matbase.Matrix(M), "Type " .. tostring(M)
                              .. " does not implement the matrix interface")
    assert(vecbase.Vector(P), "Type " .. tostring(P)
                              .. " does not implement the vector interface")
    assert(concept.Integral(P.eltype), "Permutation vector has to be of integer type")

    local T = M.eltype
    local Ts = T
    local Ts = concept.Complex(T) and T.eltype or T
    local lu = terralib.types.newstruct("LU" .. tostring(M))
    lu.entries:insert{field = "a", type = &M}
    lu.entries:insert{field = "p", type = &P}
    lu.entries:insert{field = "tol", type = Ts}
    lu:complete()
    base.AbstractBase(lu)

    terra lu:rows()
        return self.a:rows()
    end

    terra lu:cols()
        return self.a:cols()
    end

    lu.staticmethods.new = terra(a: &M, p: &P, tol: Ts)
        err.assert(a:rows() == a:cols())
        err.assert(p:size() == a:rows())
        return lu {a, p, tol}
    end

    lu.templates.factorize = template.Template:new("factorize")
    lu.templates.factorize[&lu.Self -> {}] = function(Self)
        local terra factorize(self: Self)
            var n = self:rows()
            for i = 0, n do
                self.p:set(i, i)
            end
            for i = 0, n do
                var maxA = [Ts](0)
                var imax = i
                for k = i, n do
                    var absA = mathfun.abs(self.a:get(k, i))
                    if absA > maxA then
                        maxA = absA
                        imax = k
                    end
                end

                err.assert(maxA > self.tol)

                if imax ~= i then
                    var j = self.p:get(i)
                    self.p:set(i, self.p:get(imax))
                    self.p:set(imax, j)

                    for k = 0, n do
                        var tmp = self.a:get(i, k)
                        self.a:set(i, k, self.a:get(imax, k))
                        self.a:set(imax, k, tmp)
                    end
                end

                for j = i + 1, n do
                    self.a:set(j, i, self.a:get(j, i) / self.a:get(i, i))

                    for k = i + 1, n do
                        var tmp = self.a:get(j, k)
                        self.a:set(j, k, tmp - self.a:get(j, i) * self.a:get(i, k))
                    end
                end
            end
        end
        return factorize
    end


    lu.templates.solve = template.Template:new("solve")
    lu.templates.solve[{&lu.Self, &vecbase.Vector} -> {}] = function(Self, V)
        local terra solve(self: Self, x: V)
            var n = self:rows()
            for i = 0, n do
                var idx = self.p:get(i)
                while idx < i do
                    idx = self.p:get(idx)
                end
                var tmp = x:get(i)
                x:set(i, x:get(idx))
                x:set(idx, tmp)
            end

            for i = 0, n do
                for k = 0, i do
                    x:set(i, x:get(i) - self.a:get(i, k) * x:get(k))
                end
            end

            for ii = 0, n do
                var i = n - 1 - ii
                for k = i + 1, n do
                    x:set(i, x:get(i) - self.a:get(i, k) * x:get(k))
                end
                x:set(i, x:get(i) / self.a:get(i, i))
            end
        end
        return solve
    end 

    return lu
end)

return {
    LUFactory = LUFactory,
}
