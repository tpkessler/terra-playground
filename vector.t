-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local stack = require("stack")
local err = require("assert")
local concepts = require("concepts")
local mathfun = require("mathfuns")


local VectorBase = function(V)

	local T = V.eltype
	local Stack = concepts.Stack(T)
	local Vector = concepts.Vector(T)
	assert(Stack(V), "A vector base implementation requires a valid stack implementation")

	--adds:
	--methods.reverse
	--iterator{T}
	stack.StackBase(V)

	-- Promote this to a templated method with proper concepts for callable objects
	V.methods.map = macro(function(self, other, f)
		return quote
			var size = self:size()
			err.assert(size <= other:size())
			for i = 0, size do
				other:set(i, f(self:get(i)))
			end
		in
			other
		end
	end)

	terra V:fill(a : T)
		var size = self:size()
		for i = 0, size do
			self:set(i, a)
		end
	end

	terra V:clear()
		self:fill(0)
	end

	terra V:sum()
		var size = self:size()
		var res : T = 0
		for i = 0, size do
			res = res + self:get(i)
		end
		return res
	end

	terraform V:copy(x : &S) where {S : Stack}
		err.assert(self:size() == x:size())
		var size = self:size()
		for i = 0, size do
			self:set(i, x:get(i))
		end
	end

	terraform V:swap(x : &S) where {S : Stack}
		err.assert(self:size() == x:size())
		var size = self:size()
		for i = 0, size do
			var tmp = x:get(i)
			x:set(i, self:get(i))
			self:set(i, tmp)
		end
	end

	terra V:scal(a : T)
		var size = self:size()
		for i = 0, size do
			self:set(i, a * self:get(i))
		end
	end

	terraform V:axpy(a : T, x : &S) where {S : Stack}
		err.assert(self:size() == x:size())
		var size = self:size()
		for i = 0, size do
			var yi = self:get(i)
			yi = yi + a * x:get(i)
			self:set(i, yi)
		end
	end

	terraform V:dot(x : &S) where {S : Stack}
		err.assert(self:size() == x:size())
		var size = self:size()
		var res : T = 0
		for i = 0, size do
			res = res + mathfun.conj(self:get(i)) * x:get(i)
		end
		return res
	end

	if concepts.Float(T) then
		terra V:norm()
			return mathfun.sqrt(mathfun.real(self:dot(self)))
		end
	end
	assert(Vector(V), "Incomplete implementation of vector base class")
end

return {
    VectorBase = VectorBase
}
