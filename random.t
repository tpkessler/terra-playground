local C = terralib.includecstring[[
  #include <math.h>
  #include <stdio.h>
  #include <stdlib.h>
]]
local interface = require("interface")

local ldexp = terralib.overloadedfunction("ldexp",
  {
    terra(x: double, exp: int): double return C.ldexp(x, exp) end,
    terra(x: float, exp: int): float return C.ldexpf(x, exp) end
  })

local sqrt = terralib.overloadedfunction("sqrt",
  {
    terra(x: double): double return C.sqrt(x) end,
    terra(x: float): float return C.sqrtf(x) end
  })

local cos = terralib.overloadedfunction("cos",
  {
    terra(x: double): double return C.cos(x) end,
    terra(x: float): float return C.cosf(x) end
  })

local log = terralib.overloadedfunction("log",
  {
    terra(x: double): double return C.log(x) end,
    terra(x: float): float return C.logf(x) end
  })

local RandomInterface = function(G, F, I, exp)
  F = F or double
  I = I or uint32
  exp = exp or 31
  if F ~= double and F ~= float then
    error("Unsupported floating point type " .. tostring(F))
  end
  local must_implement = {["rand_int"] = {&G} -> {I}}
  interface.assert_implemented(G, must_implement)

  local self = {}
  self.generator = G

  -- Turn random integers into random floating point numbers
  -- http://mumble.net/~campbell/tmp/random_real.c
  terra self.generator:rand_uniform(): F
    var rand_int = self:rand_int()
    return ldexp([F](rand_int) , -exp)
  end

  terra self.generator:rand_normal(m: F, s: F): F
    var u1 = self:rand_uniform()
    var u2 = self:rand_uniform()

    var r = log(u1)
    var theta = [F](2) * [F](C.M_PI) * u2
    return m + s * r * cos(theta)
  end

  terra self.generator:rand_exp(lambda: F): F
    var u = self:rand_uniform()
    return -log(u) / lambda
  end

  return self
end

local LibC = function(F)
  local struct libc {}
  terra libc:rand_int(): int64
    return [int64](C.random())
  end

  local self = RandomInterface(libc, F, int64, 31)

  self.new = macro(function(seed)
	  	return quote
		    C.srandom(seed)
          in
		    libc {}
		  end
	end)

  return self
end

-- https://digitalcommons.wayne.edu/jmasm/vol2/iss1/2/
-- page 12
local KISS = function(F)
  local struct kiss {
	  x: uint32
	  y: uint32
	  z: uint32
	  c: uint32
  }
 
  terra kiss:rand_int(): uint32
    self.x = 69069 * self.x + 12345
    self.y = (self.y) ^ (self.y << 13)
    self.y = (self.y) ^ (self.y >> 17)
    self.y = (self.y) ^ (self.y << 5)
  	var t: uint64 = [uint64](698769069) * self.z + self.c
  	self.c = t >> 32
  	self.z = [uint32](t)

  	return self.x + self.y + self.z
  end

  local self = RandomInterface(kiss, F, uint32, 32)

  self.new = macro(function(seed)
	  return `self.generator {seed, 362436000, 521288629, 7654321}
    end)

  return self
end

-- FIXME Does not work
-- https://www.pcg-random.org/download.html
local MinimalPCG = function(F)
  local struct pcg {
      state: uint64
      inc: uint64
    }

  terra pcg:rand_int(): uint32
    var oldstate = self.state
    self.state = oldstate * [uint64](6364136223846793005ull) + (self.inc or 1u)
    var xorshifted: uint32 = ((oldstate >> 18u) ^ oldstate) >> 27u
    var rot: uint32 = oldstate >> 59u
	return (xorshifted >> rot) or (xorshifted << ((-rot) and 31))
  end

  local self = RandomInterface(pcg, F, uint32, 32)

  self.new = macro(function(seed)
      return quote
	  	  var incseq = 1
	  	  var rand = self.generator {0, incseq}
		  rand.inc = (incseq << 1u) or 1u
		  rand:rand_int()
		  rand.state = rand.state + seed
		  rand:rand_int()
		in
		  rand
	  end
    end)

  return self
end

local pcg = MinimalPCG(double)
local libc = LibC(double)
local kiss = KISS(float)

terra main()
  var rng = libc.new(124)
  var n: int64 = 2000001
  var mean: double = 0
  for i: int64 = 0, n do
	var u = rng:rand_uniform()
    mean = i * mean + u
	mean = mean / (i + 1)
  end
  C.printf("%u %g\n", n, mean)
end

main()
