-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local err = require("assert")
local concepts = require("concepts")
local tmath = require("mathfuns")


local VectorBase = function(Vector)

	local T = Vector.eltype
	local Stack = concepts.Stack(T)

	assert(Stack(Vector), "A vector base implementation requires a valid stack implementation.")

    terra Vector:getbuffer()
        return self:length(), self:getdataptr()
    end

    terra Vector:fill(value : T)
        for i = 0, self:length() do
            self:set(i, value)
        end
    end

    terraform Vector:copy(other : &S) where {S : Stack}
        for i = 0, self:length() do
            self:set(i, other:get(i))
        end
    end

	terraform Vector:swap(other : &S) where {S : Stack}
		err.assert(self:length() == other:length())
		for i = 0, self:length() do
			var tmp = other:get(i)
			other:set(i, self:get(i))
			self:set(i, tmp)
		end
	end

    if concepts.Number(T) then

        terra Vector:clear()
		    self:fill(0)
	    end

        terra Vector:sum()
            var res : T = 0
            for i = 0, self:length() do
                res = res + self:get(i)
            end
            return res
        end

        terra Vector:scal(a : T)
            for i = 0, self:length() do
                self:set(i, a * self:get(i))
            end
        end

        terra Vector:axpy(a : T, x : &Vector)
            for i = 0, self:length() do
                self:set(i, self:get(i) + a * x:get(i))
            end
        end

        terra Vector:dot(other : &Vector)
            var s = T(0)
            for i = 0, self:length() do
                s = s + self:get(i) * other:get(i)
            end
            return s
        end
        
        terra Vector:norm2()
            return self:dot(self)
        end

        if concepts.Float(T) then
            terra Vector:norm() : T
                return tmath.sqrt(self:norm())
            end
		end

    end

    --sanity check: have we implemented the Vector concept interface?
    local VectorConcept = concepts.Vector(T)
    assert(VectorConcept(Vector), "Incomplete implementation of vector base class")

end


local IteratorBase = function(Vector)

    local T = Vector.eltype

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
    Vector = concepts.Vector,
    VectorBase = VectorBase,
    IteratorBase = IteratorBase
}