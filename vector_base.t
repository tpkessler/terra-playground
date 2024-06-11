local interface = require("interface")
local stack = require("stack")
local err = require("assert")

local function Vectorizer(T, I)
    I = I or int64
    local S = stack.Stacker(T, I)
    return interface.Interface:new{
        fill = T -> {},
        clear = {} -> {},
        copy = S.type -> {},
        swap = S.type -> {},
        scal = T -> {},
        axpy = {T, S.type} -> {},
        dot = S.type -> T
    }
end

local function VectorBase(V, T, I)
    local Stacker = stack.Stacker(T, I)
    Stacker:isimplemented(V)

    terra V:fill(a: T)
        var size = self:size()
        for i = 0, size do
            self:set(i, a)
        end
    end

    terra V:clear()
        self:fill(0)
    end

    local assert_size = macro(function(x, y)
        return quote
                var x_size = [x]:size()
                var y_size = [y]:size()

            in
                err.assert(x_size == y_size)
        end
    end)

    terra V:copy(x: &V)
        var size = self:size()
        assert_size(self, x)

        for i = 0, size do
            self:set(i, x:get(i))
        end
    end

    terra V:swap(x: &V)
        var size = self:size()
        assert_size(self, x)

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

    terra V:axpy(a: T, x: &V)
        var size = self:size()
        assert_size(self, x)

        for i = 0, size do
            var yi = self:get(i)
            yi = yi + a * x:get(i)
            self:set(i, yi)
        end
        
    end

    terra V:dot(x: &V)
        var size = self:size()
        assert_size(self, x)

        var res: T = 0
        for i = 0, size do
            res = res + self:get(i) * x:get(i)
        end

        return res
    end

    local Vectorizer = Vectorizer(T, I)
    Vectorizer:isimplemented(V)

    return V
end

return {
    Vectorizer = Vectorizer,
    VectorBase = VectorBase
}
