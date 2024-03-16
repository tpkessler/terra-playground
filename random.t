local C = terralib.includecstring[[
  #include <math.h>
  #include <stdio.h>
  #include <stdlib.h>
  #include "tinymt/tinymt64.h"
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

local uname = io.popen("uname", "r"):read("*a")
if uname == "Darwin\n" then
	terralib.linklibrary("./libtinymt.dylib")
elseif uname == "Linux\n" then
	terralib.linklibrary("./libtinymt.so")
else
	error("OS Unknown")
end

local Interface, AbstractSelf = unpack(require("interface"))

local ldexp = terralib.overloadedfunction("ldexp", {C.ldexp, C.ldexpf})
local sqrt = terralib.overloadedfunction("sqrt", {C.sqrt, C.sqrtf})
local cos = terralib.overloadedfunction("cos", {C.cos, C.cosf})
local log = terralib.overloadedfunction("log", {C.log, C.logf})


local RandomGenerator = function(I)
	return Interface{
		rand_int = &AbstractSelf -> I
	}
end

local RandomNumber = function(G, I, F, range)
  if F ~= double and F ~= float then
    error("Unsupported floating point type " .. tostring(F))
  end
  local RandomGenerator = RandomGenerator(I)
  RandomGenerator:isimplemented(G)

  local self = {}
  self.type = G

  -- Turn random integers into random floating point numbers
  -- http://mumble.net/~campbell/tmp/random_real.c
  terra self.type:rand_uniform(): F
    var rand_int = self:rand_int()
    return ldexp([F](rand_int) , -range)
  end

  terra self.type:rand_normal(m: F, s: F): F
    var u1 = self:rand_uniform()
    var u2 = self:rand_uniform()

    var r = log(u1)
    var theta = [F](2) * [F](C.M_PI) * u2
    return m + s * r * cos(theta)
  end

  terra self.type:rand_exp(lambda: F): F
    var u = self:rand_uniform()
    return -log(u) / lambda
  end

  return self
end

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

local LibC = function(F)
  local struct libc {}
  terra libc:rand_int(): int64
    return C.random()
  end

  local self = RandomNumber(libc, int64, F, 31)
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

-- http://www.math.sci.hiroshima-u.ac.jp/m-mat/MT/TINYMT/
local TinyMT = function(F)
    local struct tinymt {
        state: C.tinymt64_t
    }

    terra tinymt:rand_int(): uint64
        return C.tinymt64_generate_uint64_public(&self.state)
    end

	local self = RandomNumber(tinymt, uint64, F, 64)
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

  local self = RandomNumber(kiss, uint32, F, 32)
  local random_seed = read_urandom(uint32)

  self.from = macro(function(seed)
      seed = seed or random_seed()
	  return `self.type {seed, 362436000, 521288629, 7654321}
    end)

  return self
end

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

  local self = RandomNumber(pcg, uint32, F, 32)
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

local S = {Default = LibC, PCG = MinimalPCG, KISS = KISS, TinyMT = TinyMT}

return S
