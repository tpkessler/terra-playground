local assert = require "assert"
local C = terralib.includecstring[[
  #include <math.h>
]]

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

local RandomInterface = function(G, I, F)
  local I = I or uint32
  local F = F or double
  if F ~= double and F ~= float then
    error("Unsupported floating point type " .. tostring(F))
  end
  local random = {}
  random.generator = G
  
  terra random.generator:rand_int(): I assert.NotImplementedError() end

  -- Turn random integers to random floating point numbers
  -- http://mumble.net/~campbell/tmp/random_real.c
  local exp = sizeof(I)
  terra random.generator:rand_uniform(): F
    var rand_int = self:rand_int()
    return ldexp([F](rand_int) , -exp)
  end

  terra random.generator:rand_normal(m: F, s: F): F
    var u1 = self:rand_uniform()
    var u2 = self:rand_uniform()

    var r = log(u1)
    var theta = [F](2) * [F](C.M_PI) * u2
    return m + s * r * cos(theta)
  end

  terra random.generator:rand_exp(lambda: F): F
    var u = self:rand_uniform()
    return -log(u) / lambda
  end

  return random
end

-- https://www.pcg-random.org/download.html
local MinimalPCG = function(F)
  local struct pcg {
      state: uint64
      inc: uint64
    }

  local self = RandomInterface(pcg, uint32, F)
  self.new = macro(function(seed)
      return `self.generator {seed, 0}
    end)

  -- Figure out the correct type
  terra self.generator:rand_int(): uint32
    var oldstate = self.state
    self.state = oldstate * [uint64](6364136223846793005ULL) + (self.inc or 1)
    var xorshifted: uint32 = ((oldstate >> [uint32](18)) ^ oldstate) >> [uint32](27)
    var rot: uint32 = oldstate >> [uint32](59)
    return (xorshifted >> rot) or (xorshifted << ((-rot) and 31))
  end

  return self
end

local pcg = MinimalPCG(double)

terra main()
  var rng = pcg.new(123)
  var u = rng:rand_uniform()
end

main()
