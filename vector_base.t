local err = require("assert")
local template = require("template")
local concept = require("concept")

local Stack = concept.AbstractInterface:new("Stack", {
  size = {} -> concept.UInteger,
  get = concept.UInteger -> concept.Number,
  set = {concept.UInteger, concept.Number} -> {},
})

local StackPtr = Stack + concept.Ptr(Stack)

local Vector = concept.AbstractInterface:new("Vector")
Vector:addmethod{
  fill = concept.Number -> {},
  clear = {} -> {},
  sum  = {} -> {concept.Number},
  -- BLAS operations
  copy = StackPtr -> {},
  swap = StackPtr -> {},
  scal = concept.Number -> {},
  axpy = {concept.Number, StackPtr} -> {},
  dot = StackPtr -> concept.Number
}
Vector = Stack * Vector

local VectorBase = function(V, T)
  assert(Stack(V),
    "A vector base implementation requires a valid stack implementation")
  T = T or double

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
  V.templates.clear[{V.Self} -> {}] = function(Self)
    local terra clear(self: Self)
      self:fill(0)
    end
    return clear
  end

  V.templates.sum = template.Template:new("sum")
  V.templates.sum[{StackPtr} -> {concept.Number}] = function(Self)
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
	V.templates.copy[{StackPtr, StackPtr} -> {}] = function(Self, S)
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
	V.templates.swap[{StackPtr, StackPtr} -> {}] = function(Self, S)
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
	V.templates.scal[{StackPtr, concept.Number} -> {}] = function(Self, T)
    local terra scal(self: Self, a: T)
      var size = self:size()
      for i = 0, size do
        self:set(i, a * self:get(i))
      end
    end
    return scal
	end

	V.templates.axpy = template.Template:new("axpy")
	V.templates.axpy[{StackPtr, concept.Number, StackPtr} -> {}] = function(Self, T, S)
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
	V.templates.dot[{StackPtr, StackPtr} -> {concept.Number}] = function(Self, S)
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
end

return {
    Vector = Vector,
    VectorBase = VectorBase
}
