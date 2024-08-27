local stack = require("stack")
local err = require("assert")
local template = require("template")
local concept = require("concept")

local Vector = concept.AbstractInterface:new("Vector")
local Stack = stack.Stack
Vector:inheritfrom(Stack)
Vector:addmethod{
  fill = concept.Number -> {},
  clear = {} -> {},
  sum  = {} -> concept.Number,
  -- BLAS operations
  copy = &Stack -> {},
  swap = &Stack -> {},
  scal = concept.Number -> {},
  axpy = {concept.Number, &Stack} -> {},
  dot = &Stack -> concept.Number
}

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

  V.templates.fill = template.Template:new("fill")
  V.templates.fill[{&V.Self, concept.Number} -> {}] = function(Self, T)
    local terra fill(self: Self, a: T)
      var size = self:size()
      for i = 0, size do
        self:set(i, a)
      end
    end
    return fill
  end

  V.templates.clear = template.Template:new("clear")
  V.templates.clear[{&V.Self} -> {}] = function(Self)
    local terra clear(self: Self)
      self:fill(0)
    end
    return clear
  end

  V.templates.sum = template.Template:new("sum")
  V.templates.sum[{&V.Self} -> {concept.Number}] = function(Self)
    local terra sum(self: Self)
      var size = self:size()
      var res: T = 0
      for i = 0, size do
        res = res + self:get(i)
      end
      return res
    end
    return sum
  end

  V.templates.copy = template.Template:new("copy")
	V.templates.copy[{&V.Self, &Stack} -> {}] = function(Self, S)
	  local terra copy(self: Self, x: S)
			err.assert(self:size() == x:size())
      var size = self:size()
  		for i = 0, size do
  			self:set(i, x:get(i))
  		end
  	end
  	return copy
	end

	V.templates.swap = template.Template:new("swap")
	V.templates.swap[{&V.Self, &Stack} -> {}] = function(Self, S)
    local terra swap(self: Self, x: S)
  		err.assert(self:size() == x:size())
      var size = self:size()
      for i = 0, size do
        var tmp = x:get(i)
        x:set(i, self:get(i))
        self:set(i, tmp)
      end
    end
    return swap
	end

	V.templates.scal = template.Template:new("scal")
	V.templates.scal[{&V.Self, concept.Number} -> {}] = function(Self, T)
    local terra scal(self: Self, a: T)
      var size = self:size()
      for i = 0, size do
        self:set(i, a * self:get(i))
      end
    end
    return scal
	end

	V.templates.axpy = template.Template:new("axpy")
	V.templates.axpy[{&V.Self, concept.Number, &Stack} -> {}] = function(Self, T, S)
    local terra axpy(self: Self, a: T, x: S)
    	err.assert(self:size() == x:size())
      var size = self:size()
      for i = 0, size do
        var yi = self:get(i)
        yi = yi + a * x:get(i)
        self:set(i, yi)
      end
    end
    return axpy
	end

	-- TODO Include complex numbers
	V.templates.dot = template.Template:new("dot")
	V.templates.dot[{&V.Self, &Stack} -> {concept.Number}] = function(Self, S)
    local terra dot(self: Self, x: S)
    	err.assert(self:size() == x:size())
      var size = self:size()

      var res: T = 0
      for i = 0, size do
          res = res + self:get(i) * x:get(i)
      end
    end
    return res
  end

  assert(Vector(V), "Incomplete implementation of vector base class")
  Vector:addimplementations{V}
end

return {
    Vector = Vector,
    VectorBase = VectorBase
}
