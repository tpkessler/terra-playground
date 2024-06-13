local interface = require("interface")
local stack = require("stack")
local err = require("assert")

local Vectorizer = terralib.memoize(function(T, I)
    I = I or int64
    local S = stack.Stacker(T, I)
    return interface.Interface:new{
		size = {} -> I,
		set = {I, T} -> {},
		get = I -> T,
        fill = T -> {},
        clear = {} -> {},
        copy = S -> {},
        swap = S -> {},
        scal = T -> {},
        axpy = {T, S} -> {},
        dot = S -> T
    }
end)

local VectorBase = terralib.memoize(function(V, T, I)
    local S = stack.Stacker(T, I)
	S:isimplemented(V)

    terra V:fill(a: T)
        var size = self:size()
        for i = 0, size do
            self:set(i, a)
        end
    end

    terra V:clear()
        self:fill(0)
    end

    terra V:copy(x: S)
		err.assert(self:size() == x:size())
        var size = self:size()

        for i = 0, size do
            self:set(i, x:get(i))
        end
    end

    terra V:swap(x: S)
		err.assert(self:size() == x:size())
        var size = self:size()

        for i = 0, size do
            var tmp = x:get(i)
            x:set(i, self:get(i))
            self:set(i, tmp)
        end
    end

    terra V:scal(a: T)
        var size = self:size()

        for i = 0, size do
            self:set(i, a * self:get(i))
        end
    end

    terra V:axpy(a: T, x: S)
		err.assert(self:size() == x:size())
        var size = self:size()

        for i = 0, size do
            var yi = self:get(i)
            yi = yi + a * x:get(i)
            self:set(i, yi)
        end
        
    end

    terra V:dot(x: S)
		err.assert(self:size() == x:size())
        var size = self:size()

        var res: T = 0
        for i = 0, size do
            res = res + self:get(i) * x:get(i)
        end

        return res
    end

    local Vectorizer = Vectorizer(T, I)
    Vectorizer:isimplemented(V)

    return V
end)

return {
    Vectorizer = Vectorizer,
    VectorBase = VectorBase
}
