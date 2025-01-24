-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local C = terralib.includecstring[[
  #include <stdio.h> // fopen()
  #include <stdlib.h> // random()
  #include <math.h>
]]
local base = require("base")
local concepts = require("concepts")
local err = require("assert")

import "terraform"

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

local Integer = concepts.Integer
local concept PseudoRNG(I) where {I: Integer}
	terra Self:random_integer(): I end
	Self.traits.inttype = I
	Self.traits.range = concepts.traittag
end

local BLASFloat = concepts.BLASFloat
local concept RandomDistribution(T) where {T: BLASFloat}
	terra Self:random_uniform(): T end
	terra Self:random_normal(mean: T, variance: T): T end
	terra Self:random_exponential(frequency: T): T end
	Self.traits.rettype = T
end

local PseudoRandomDistributionBase = terralib.memoize(function(G, F)
	local Integer = concepts.Integer
	local I = G.traits.inttype
	assert(I ~= nil, "RNG must have a well-defined return type")
	local PseudoRNG = PseudoRNG(I)
	assert(
		PseudoRNG(G),
		"Generator type does not satisfies the PseudoRNG interface"
	)

	local BLASFloat = concepts.BLASFloat
	assert(BLASFloat(F), "Return type must be float or double")

	terra G:random_uniform(): F
		var random_integer = self:random_integer()
		return ldexp([F](random_integer) , -[G.traits.range])
	end

	terra G:random_normal(m: F, s: F): F
		var u1 = self:random_uniform()
		var u2 = self:random_uniform()

		var r = sqrt(2 * log(1 / u1))
		var theta: F = 2 * [F](C.M_PI) * u2
		return m + s * r * cos(theta)
	end

	terra G:random_exponential(lambda: F): F
		var u = self:random_uniform()
		return -log(u) / lambda
	end

	G.traits.rettype = F

	local RandomDistribution = RandomDistribution(F)
	assert(RandomDistribution(G))
end)

local terraform getrandom(x: &T) where {T}
	var f = C.fopen("/dev/urandom", "r")
	defer C.flose(f)
	err.assert(f ~= nil)

	var num_read = C.fread(x, sizeof(T), 1, f)
	err.assert(num_read == 1)
end

-- Wrapper around the random number generator of the C standard library
-- TODO Port it to concepts and terraform
local LibC = terralib.memoize(function(F)
	local struct libc {}
	local I = int64

	function libc.metamethods.__typename(self)
		return ("LibC(%s)"):format(tostring(F))
	end
	
	base.AbstractBase(libc)
	libc.traits.inttype = I
	libc.traits.range = 31
	
	terra libc:random_integer(): I
		return C.random()
	end

	local PseudoRNG = PseudoRNG(I)
	assert(PseudoRNG(libc))

	PseudoRandomDistributionBase(libc, F)

	local Integer = concepts.Integer
	terraform libc.staticmethods.new(seed: J) where {J: Integer}
		C.srandom(seed)
		return libc {}
	end

	return libc
end)

-- A simple random number generator,
-- Keep It Simple Stupid, see
-- https://digitalcommons.wayne.edu/jmasm/vol2/iss1/2/
-- page 12
local KISS = terralib.memoize(function(F)
	local I = uint32
	local struct kiss {
		x: I
		y: I
		z: I
		c: I
	}

	function kiss.metamethods.__typename(self)
		return ("KISS(%s)"):format(tostring(F))
	end

	base.AbstractBase(kiss)
	kiss.traits.inttype = I
	kiss.traits.range = 32

	terra kiss:random_integer(): I
		self.x = 69069 * self.x + 12345
		self.y = (self.y) ^ (self.y << 13)
		self.y = (self.y) ^ (self.y >> 17)
		self.y = (self.y) ^ (self.y << 5)
		var t: uint64 = [uint64](698769069) * self.z + self.c
		self.c = t >> 32
		self.z = [uint32](t)

		return self.x + self.y + self.z
	end

	local PseudoRNG = PseudoRNG(I)
	assert(PseudoRNG(kiss))

	PseudoRandomDistributionBase(kiss, F)

	local Integer = concepts.Integer
	terraform kiss.staticmethods.new(seed: J) where {J: Integer}
		return kiss {seed, 362436000, 521288629, 7654321}
	end

	return kiss
end)

-- A minimal, 32 bit implemenation of the PCG generator, see
-- https://www.pcg-random.org/download.html
local MinimalPCG = terralib.memoize(function(F)
	local I = uint32
	local struct pcg {
		state: uint64
		inc: uint64
	}

	function pcg.metamethods.__typename(self)
		return ("MinimalPCG(%s)"):format(tostring(F))
	end

	base.AbstractBase(pcg)
	pcg.traits.inttype = I
	pcg.traits.range = 32

	local I = uint32
	terra pcg:random_integer(): I
		var oldstate = self.state
		self.state = (
			oldstate * [uint64](6364136223846793005ull) + (self.inc or 1u)
		)
		var xorshifted: uint32 = ((oldstate >> 18u) ^ oldstate) >> 27u
		var rot: uint32 = oldstate >> 59u
		return (xorshifted >> rot) or (xorshifted << ((-rot) and 31))
	end

	local PseudoRNG = PseudoRNG(I)
	assert(PseudoRNG(pcg))

	PseudoRandomDistributionBase(pcg, F)

	local Integer = concepts.Integer
	terraform pcg.staticmethods.new(
		seed: J1, stream: J2
	) where {J1: Integer, J2: Integer}
		var rng = pcg {0, stream}
		rng.inc = (stream << 1u) or 1u
		rng:random_integer()
		rng.state = rng.state + seed
		rng:random_integer()
		return rng
	end

	terraform pcg.staticmethods.new(seed: J) where {J: Integer}
		return [pcg.staticmethods.new](seed, 1)
	end

	return pcg
end)

-- Wrapper around the full implementation of the PCG generator (64 bit), see
-- https://www.pcg-random.org/
local pcgvar = setmetatable(
	terralib.includec("./pcg/pcg_variants.h"),
	{__index = (
			function(self, key)
				return self["pcg_" .. key] or rawget(self, key)
			end
		)
	}
)
local PCG = terralib.memoize(function(F)
	local I = uint64
	-- FIXME Terra doesn't parse the definition of the struct corretly,
	-- possibly because it's included in an ifdef clause. But we know that
	-- the type has size 2 * 128 = 4 * 64 bits, so we define a type of
	-- equivalent size here and cast to the corresponding pointer when
	-- necessary. 
	local pcg_ = pcgvar.state_setseq_128
	assert(sizeof(pcg_) == 0)
	local struct pcg {
		a: uint64
		b: uint64
		c: uint64
		d: uint64
	}
	assert(sizeof(pcg) == 32)

	local struct uint128 {
		hi: uint64
		lo: uint64
	}

	function uint128.metamethods.__cast(from, to, exp)
		if to == uint128 then
			return `uint128 {0, exp}
		else
			error("Invalid integer type for uint128")
		end
	end


	function pcg.metamethods.__typename(self)
		return ("PCG(%s)"):format(tostring(F))
	end

	base.AbstractBase(pcg)
	pcg.traits.inttype = I
	pcg.traits.range = 64

	terra pcg:random_integer(): uint64
		return pcgvar.setseq_128_xsl_rr_64_random_r([&pcg_](self))
	end

	local PseudoRNG = PseudoRNG(I)
	assert(PseudoRNG(pcg))

	PseudoRandomDistributionBase(pcg, F)


	local Integer = concepts.Integer
	terraform pcg.staticmethods.new(
		seed: J1, stream: J2
	) where {J1: Integer, J2: Integer}
		var rng: pcg
		var seed128 = [uint128](seed)
		var stream128 = [uint128](stream)
		pcgvar.setseq_128_void_srandom_r([&pcg_](&rng), &seed128, &stream128)
		return rng
	end

	terraform pcg.staticmethods.new(seed: J) where {J: Integer}
		return [pcg.staticmethods.new](seed, 1)
	end

	return pcg
end)

return {
	LibC = LibC,
	KISS = KISS,
	MinimalPCG = MinimalPCG,
	PCG = PCG,
	getrandom = getrandom,
}
