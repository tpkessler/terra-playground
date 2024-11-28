-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local stack = require("stack")
local err = require("assert")
local concept = require("concept")
local mathfun = require("mathfuns")

local Number = concept.Number
local Stack = stack.Stack
local struct Vector(concept.Base) {}
Vector:inherit(Stack)
Vector.methods.fill = {&Vector, Number} -> {}
Vector.methods.clear = {&Vector} -> {}
Vector.methods.sum = {&Vector} -> Number
-- BLAS operations
Vector.methods.copy = {&Vector, &Stack} -> {}
Vector.methods.swap = {&Vector, &Stack} -> {}
Vector.methods.scal = {&Vector, Number} -> {}
Vector.methods.axpy = {&Vector, Number, &Stack} -> {}
Vector.methods.dot = {&Vector, &Stack} -> {Number}
-- Vector.methods.norm = {&Vector} -> {Number}

local VectorBase = function(V)
	assert(Stack(V),
		"A vector base implementation requires a valid stack implementation")
	local T = V.eltype

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

	terraform V:fill(a : T) where {T : concept.Number}
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

	terraform V:scal(a : T) where {T : concept.Number}
		var size = self:size()
		for i = 0, size do
			self:set(i, a * self:get(i))
		end
	end

	terraform V:axpy(a : T, x : &S) where {T : concept.Number, S : Stack}
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

	if concept.Float(T) then
		terra V:norm()
			return mathfun.sqrt(mathfun.real(self:dot(self)))
		end
	end

	assert(Vector(V), "Incomplete implementation of vector base class")
end

return {
    Vector = Vector,
    VectorBase = VectorBase
}
