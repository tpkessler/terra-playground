-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local err = require("assert")
local concepts = require("concepts")
local tmath = require("tmath")
local range = require("range")


local VectorBase = function(Vector)

	local T = Vector.traits.eltype
	local Concept = {
		Stack = concepts.Stack(T),
		Vector = concepts.Vector(T)
	}

	assert(Concept.Stack(Vector), "A vector base implementation requires a valid stack implementation")

    terra Vector:getbuffer()
        return self:length(), self:getdataptr()
    end

    terra Vector:fill(value : T)
        for i = 0, self:length() do
            self:set(i, value)
        end
    end

    terraform Vector:copy(other : &S) where {S : Concept.Stack}
        for i = 0, self:length() do
            self:set(i, other:get(i))
        end
    end

	terraform Vector:swap(other : &S) where {S : Concept.Stack}
		err.assert(self:length() == other:length())
		for i = 0, self:length() do
			var tmp = other:get(i)
			other:set(i, self:get(i))
			self:set(i, tmp)
		end
	end

    if concepts.Number(T) then

        terraform Vector:scal(a : T)
            for i = 0, self:length() do
                self:set(i, a * self:get(i))
            end
        end

        terraform Vector:axpy(a : T, x : &X) where {X : Concept.Stack}
            err.assert(self:length() == x:length())
            for i = 0, self:length() do
                self:set(i, self:get(i) + a * x:get(i))
            end
        end

        terraform Vector:dot(other : &X) where {X : Concept.Stack}
            err.assert(self:length() == other:length())
            var s = T(0)
            for i = 0, self:length() do
                s = s + self:get(i) * other:get(i)
            end
            return s
        end

        terraform Vector:sum()
            var res : T = 0
            for i = 0, self:length() do
                res = res + self:get(i)
            end
            return res
        end

        terraform Vector:norm2()
            return self:dot(self)
        end

        if concepts.Float(T) then
            terraform Vector:norm()
                return tmath.sqrt(self:norm2())
            end
        end

    end

end

local IteratorBase = function(Vector)

    local T = Vector.traits.eltype

    local struct iterator{
        -- Reference to vector over which we iterate.
        -- It's used to check the length of the iterator
        parent : &Vector
        -- Reference to the current element held in the smart block
        ptr : &T
    }

    terra Vector:getiterator()
        return iterator {self, self:getdataptr()}
    end

    terra iterator:getvalue()
        return @self.ptr
    end

    terra iterator:next()
        self.ptr = self.ptr + 1
    end

    terra iterator:isvalid()
        return (self.ptr - self.parent:getdataptr()) < self.parent:length()
    end
    
    range.Base(Vector, iterator)

end


return {
    VectorBase = VectorBase,
    IteratorBase = IteratorBase
}
