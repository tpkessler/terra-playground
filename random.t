local C = terralib.includecstring[[
  #include <math.h>
  #include <stdio.h>
  #include <stdlib.h>
  #include "tinymt/tinymt64.h"
  #include "pcg/pcg_variants.h"
]]
-- terra does not import macros other than those that set a constant number
-- this causes an issue on macos, where 'stderr', etc are defined by referencing
-- to another implementation in a file. So we set them here. 
if rawget(C, "stderr") == nil and rawget(C, "__stderrp") ~= nil then
    rawset(C, "stderr", C.__stderrp)
end
if rawget(C, "stdin") == nil and rawget(C, "__stdinp") ~= nil then
    rawset(C, "stdin", C.__stdinp)
end 
if rawget(C, "stdout") == nil and rawget(C, "__stdoutp") ~= nil then
    rawset(C, "stdout", C.__stdoutp)
end 

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

local Interface, AbstractSelf = unpack(require("interface"))

local ldexp = terralib.overloadedfunction("ldexp", {C.ldexp, C.ldexpf})
local sqrt = terralib.overloadedfunction("sqrt", {C.sqrt, C.sqrtf})
local cos = terralib.overloadedfunction("cos", {C.cos, C.cosf})
local log = terralib.overloadedfunction("log", {C.log, C.logf})


-- Interface for pseudo random number generator.
-- Given an interal state, subsequent calls to rand_int() generate
-- a sequence of uncorrelated integers of type I.
local PseudoRandomizer = function(I)
	assert(I:isintegral(), "Return value of PRNG must be an integral type")
	return Interface{
		rand_int = &AbstractSelf -> I
	}
end

-- Interface for the sampling of random numbers according to probability distributions.
-- Currently supported are:
-- the uniform distribution on [0, 1];
-- the normal distribution with given mean and standard deviation;
-- the exponential distribution with given rate.
local RandomDistributer = function(F)
	assert(F:isfloat(), "Return value must be float or double")
	return Interface{
		rand_uniform = &AbstractSelf -> F,
		rand_normal = {&AbstractSelf, F, F} -> F,
		rand_exp = {&AbstractSelf, F} -> F
	}
end

-- Implementation of RandomDistributer on top of PseudoRandomizer
-- G is an implementation of RandomDistributer;
-- I is the integral return type of G;
-- F is the return type for the RandomDistributer interface;
-- range is the number of random bytes, typically 32 or 64.
local PRNG = function(G, I, F, range)
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

    var r = log(u1)
    var theta = [F](2) * [F](C.M_PI) * u2
    return m + s * r * cos(theta)
  end

  terra G:rand_exp(lambda: F): F
    var u = self:rand_uniform()
    return -log(u) / lambda
  end

  local RandomDistributer = RandomDistributer(F)
  RandomDistributer:isimplemented(G)

  return G
end

-- Read a truely random value of type T from /dev/urandom
function read_urandom(T)
    local terra impl()
        var f = C.fopen("/dev/urandom", "r")
        if f == nil then
            C.fprintf(C.stderr, "Cannot open /dev/urandom")
            C.abort()
        end

        var x: T
        var num_read = C.fread(&x, sizeof(T), 1, f)
        if num_read ~= 1 then
            C.fprintf(C.stderr, "Cannot read from /dev/urandom")
            C.abort()
        end
        C.fclose(f)

        return x
    end

    return impl
end

-- Wrapper around the random number generator of the C standard library
local LibC = function(F)
  local struct libc {}
  terra libc:rand_int(): int64
    return C.random()
  end

  local self = {}
  self.type = PRNG(libc, int64, F, 31)

  local random_seed = read_urandom(uint32)

  self.from = macro(function(seed)
        seed = seed or random_seed()
	  	return quote
		    C.srandom(seed)
          in
		    libc {}
		  end
	end)

  return self
end

-- The tiny Mersenner twister (64 bit), see
-- http://www.math.sci.hiroshima-u.ac.jp/m-mat/MT/TINYMT/
local TinyMT = function(F)
    local struct tinymt {
        state: C.tinymt64_t
    }

    terra tinymt:rand_int(): uint64
        return C.tinymt64_generate_uint64_public(&self.state)
    end

	local self = {}
	self.type = PRNG(tinymt, uint64, F, 64)
	local random_seed = read_urandom(uint64)

	self.from = macro(function(seed)
		seed = seed or random_seed()
		return quote
				var tiny: C.tinymt64_t
				-- Starting values from readme.
				tiny.mat1 = 0
				tiny.mat2 = 0x65980cb3
				tiny.tmat = 0xeb38facf
				C.tinymt64_init(&tiny, seed)
				var rand = self.type {tiny}
			in
				rand
		end

	end)

	return self
end

-- A simple random number generator,
-- Keep It Simple Stupid, see
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

  local self = {}
  self.type = PRNG(kiss, uint32, F, 32)
  local random_seed = read_urandom(uint32)

  self.from = macro(function(seed)
      seed = seed or random_seed()
	  return `self.type {seed, 362436000, 521288629, 7654321}
    end)

  return self
end

-- A minimal, 32 bit implemenation of the PCG generator, see
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

  local self = {}
  self.type = PRNG(pcg, uint32, F, 32)
  local random_seed = read_urandom(uint32) 

  self.from = macro(function(seed, stream)
      seed = seed or random_seed()
      stream = stream or 1
      return quote
	  	  var rand = self.type {0, stream}
		  rand.inc = (stream << 1u) or 1u
		  rand:rand_int()
		  rand.state = rand.state + seed
		  rand:rand_int()
		in
		  rand
	  end
    end)

  return self
end

-- Wrapper around the full implementation of the PCG generator (64 bit), see
-- https://www.pcg-random.org/
local PCG = function(F)
	local struct pcg{
		state: C.pcg64_random_t
	}

	terra pcg:rand_int(): uint64
		return C.pcg_setseq_128_xsl_rr_64_random_r(&self.state)
	end

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

	local self = {}
	self.type = PRNG(pcg, uint64, F, 64)
	local random_seed = read_urandom(uint128)

	self.from = macro(function(seed, stream)
		seed = seed and quote var a: uint128 = [seed] in &a end or quote var a = random_seed() in &a end
		stream = stream and quote var a: uint128 = [stream] in &a end or quote var a: uint128 = 1 in &a end
		return quote
				var rand: self.type
				C.pcg_setseq_128_void_srandom_r(&rand.state, [seed], [stream])
			in
				rand
			end
	end)

	return self
end

local S = {PseudoRandomizer = PseudoRandomizer,
		   RandomDistributer = RandomDistributer,
		   Default = LibC,
		   PCG = PCG,
		   MinimalPCG = MinimalPCG,
		   KISS = KISS,
		   TinyMT = TinyMT}

return S
