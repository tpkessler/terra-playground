local interface = require("interface")
local stack = require("stack")
local err = require("assert")
local template = require("template")
local concept = require("concept")

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

	local impl = {}

	-- TODO Make this proper templates
	impl.copy = template.Template:new()
	local Stack = stack.Stack(T, I)
	impl.copy[{Stack, Stack}] = function(T1, T2)
		return terra(self: T1, x: T2)
			err.assert(self:size() == x:size())
	        var size = self:size()
			for i = 0, size do
				self:set(i, x:get(i))
			end
		end
	end

	rawset(V, "template", impl)

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
	-- TODO Let interface implementation also check for templated methods
    -- Vectorizer:isimplemented(V)

    return V
end)

return {
    Vectorizer = Vectorizer,
    VectorBase = VectorBase
}
