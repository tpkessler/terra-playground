local C = terralib.includecstring[[
  #include <stdio.h> // fopen()
  #include <stdlib.h> // random()
  #include <math.h>
  #include "tinymt/tinymt64.h"
  #include "pcg/pcg_variants.h"
]]
local interface = require("interface")
local err = require("assert")

-- Compile C libraries with make first before using this module
local uname = io.popen("uname", "r"):read("*a")
if uname == "Darwin\n" then
	terralib.linklibrary("./libtinymt.dylib")
	terralib.linklibrary("./libpcg.dylib")
elseif uname == "Linux\n" then
	terralib.linklibrary("./libtinymt.so")
	terralib.linklibrary("./libpcg.so")
else
	error("OS Unknown")
end

local ldexp = terralib.overloadedfunction("ldexp", {C.ldexp, C.ldexpf})
local sqrt = terralib.overloadedfunction("sqrt", {C.sqrt, C.sqrtf})
local cos = terralib.overloadedfunction("cos", {C.cos, C.cosf})
local log = terralib.overloadedfunction("log", {C.log, C.logf})


-- Interface for pseudo random number generator.
-- Given an interal state, subsequent calls to rand_int() generate
-- a sequence of uncorrelated integers of type I.
local PseudoRandomizer = terralib.memoize(function(I)
	assert(I:isintegral(), "Return value of PRNG must be an integral type")
	return interface.Interface:new{
		rand_int = {} -> I
	}
end)

-- Interface for the sampling of random numbers according to probability distributions.
-- Currently supported are:
-- the uniform distribution on [0, 1];
-- the normal distribution with given mean and standard deviation;
-- the exponential distribution with given rate.
local RandomDistributer = terralib.memoize(function(F)
	assert(F:isfloat(), "Return value must be float or double")
	return interface.Interface:new{
		rand_uniform = {} -> F,
		rand_normal = {F, F} -> F,
		rand_exp = F -> F
	}
end)

-- Implementation of RandomDistributer on top of PseudoRandomizer
-- G is an implementation of RandomDistributer;
-- I is the integral return type of G;
-- F is the return type for the RandomDistributer interface;
-- range is the number of random bytes, typically 32 or 64.
local PRNGBase = terralib.memoize(function(G, I, F, range)
  if F ~= double and F ~= float then
    error("Unsupported floating point type " .. tostring(F))
  end
  local PseudoRandomizer = PseudoRandomizer(I)
  PseudoRandomizer:isimplemented(G)

  -- Turn random integers into random floating point numbers
  -- http://mumble.net/~campbell/tmp/random_real.c
  terra G:rand_uniform(): F
    var rand_int = self:rand_int()
    return ldexp([F](rand_int) , -range)
  end

  terra G:rand_normal(m: F, s: F): F
    var u1 = self:rand_uniform()
    var u2 = self:rand_uniform()

    var r = sqrt(2 * log(1 / u1))
    var theta = [F](2) * [F](C.M_PI) * u2
    return m + s * r * cos(theta)
  end

  terra G:rand_exp(lambda: F): F
    var u = self:rand_uniform()
    return -log(u) / lambda
  end

  local RandomDistributer = RandomDistributer(F)
  RandomDistributer:isimplemented(G)
end)

-- Read a truely random value of type T from /dev/urandom
local read_urandom = terralib.memoize(function(T)
    local terra impl()
        var f = C.fopen("/dev/urandom", "r")
		err.assert(f ~= nil)

        var x: T
        var num_read = C.fread(&x, sizeof(T), 1, f)
		err.assert(num_read == 1)
        C.fclose(f)

        return x
    end

    return impl
end)

-- Wrapper around the random number generator of the C standard library
local LibC = terralib.memoize(function(F)
  local struct libc {}
  terra libc:rand_int(): int64
    return C.random()
  end

  PRNGBase(libc, int64, F, 31)


  local random_seed = read_urandom(uint32)
  local from = macro(function(seed)
        seed = seed or random_seed()
	  	return quote
		    C.srandom(seed)
          in
		    libc {}
		  end
	end)

  local static_methods = {
	from = from
  }
  libc.metamethods.__getmethod = function(Self, method)
	return libc.methods[method] or static_methods[method]
  end

  return libc
end)

-- The tiny Mersenner twister (64 bit), see
-- http://www.math.sci.hiroshima-u.ac.jp/m-mat/MT/TINYMT/
local TinyMT = terralib.memoize(function(F)
    local struct tinymt {
        state: C.tinymt64_t
    }

    terra tinymt:rand_int(): uint64
        return C.tinymt64_generate_uint64_public(&self.state)
    end

	PRNGBase(tinymt, uint64, F, 64)

	local random_seed = read_urandom(uint64)
	local from = macro(function(seed)
		seed = seed or random_seed()
		return quote
				var tiny: C.tinymt64_t
				-- Starting values from readme.
				tiny.mat1 = 0
				tiny.mat2 = 0x65980cb3
				tiny.tmat = 0xeb38facf
				C.tinymt64_init(&tiny, seed)
				var rand = tinymt {tiny}
			in
				rand
		end

	end)

	local static_methods = {
		from = from
	}
	tinymt.metamethods.__getmethod = function(Self, method)
		return tinymt.methods[method] or static_methods[method]
	end

	return tinymt
end)

-- A simple random number generator,
-- Keep It Simple Stupid, see
-- https://digitalcommons.wayne.edu/jmasm/vol2/iss1/2/
-- page 12
local KISS = terralib.memoize(function(F)
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

  PRNGBase(kiss, uint32, F, 32)

  local random_seed = read_urandom(uint32)
  local from = macro(function(seed)
      seed = seed or random_seed()
	  return `kiss {seed, 362436000, 521288629, 7654321}
  end)

  local static_methods = {
	from = from
  }
  kiss.metamethods.__getmethod = function(Self, method)
	return kiss.methods[method] or static_methods[method]
  end

  return kiss
end)

-- A minimal, 32 bit implemenation of the PCG generator, see
-- https://www.pcg-random.org/download.html
local MinimalPCG = terralib.memoize(function(F)
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

  PRNGBase(pcg, uint32, F, 32)

  local random_seed = read_urandom(uint32) 
  local from = macro(function(seed, stream)
      seed = seed or random_seed()
      stream = stream or 1
      return quote
	  	  var rand = pcg {0, stream}
		  rand.inc = (stream << 1u) or 1u
		  rand:rand_int()
		  rand.state = rand.state + seed
		  rand:rand_int()
		in
		  rand
	  end
    end)

  local static_methods = {
	from = from
  }
  pcg.metamethods.__getmethod = function(Self, method)
	return pcg.methods[method] or static_methods[method]
  end

  return pcg
end)

-- Wrapper around the full implementation of the PCG generator (64 bit), see
-- https://www.pcg-random.org/
local PCG = terralib.memoize(function(F)
	local struct pcg{
		state: C.pcg64_random_t
	}

	terra pcg:rand_int(): uint64
		return C.pcg_setseq_128_xsl_rr_64_random_r(&self.state)
	end

	PRNGBase(pcg, uint64, F, 64)

	local struct uint128 {
		lo: uint64
		hi: uint64
	}
	function uint128.metamethods.__cast(from, to, exp)
		if to == uint128 then
			return `uint128 {exp, 0}
		else
			error("Invalid integer type for uint128")
		end
	end
	local random_seed = read_urandom(uint128)
	local from = macro(function(seed, stream)
		seed = seed
				and quote var a: uint128 = [seed] in &a end
				or quote var a = random_seed() in &a end
		stream = stream
				and quote var a: uint128 = [stream] in &a end
				or quote var a: uint128 = 1 in &a end
		return quote
				var rand: pcg
				C.pcg_setseq_128_void_srandom_r(&rand.state, [seed], [stream])
			in
				rand
			end
	end)

	local static_methods = {
		from = from
	}
	pcg.metamethods.__getmethod = function(Self, method)
		return pcg.methods[method] or static_methods[method]
	end

	return pcg
end)

return {
	PseudoRandomizer = PseudoRandomizer,
	RandomDistributer = RandomDistributer,
	Default = LibC,
	PCG = PCG,
	MinimalPCG = MinimalPCG,
	KISS = KISS,
	TinyMT = TinyMT,
}
