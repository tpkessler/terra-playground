-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local base = require("base")
local concepts = require("concepts")
local tmath = require("tmath")
local vecmath = require("vecmath")

import "terraform"

local C = terralib.includec("stdio.h")

local VectorPCG = terralib.memoize(function(F, N)
    local I = uint32
    local SIMD = vector(F, N)
    local SIMD64 = vector(uint64, N)
    local SIMD32 = vector(uint32, N)
	local struct pcg {
		state: SIMD64
		inc: SIMD64
	}

	function pcg.metamethods.__typename(self)
		return ("VectorPCG(%d, %s)"):format(N, tostring(F))
	end

	base.AbstractBase(pcg)
	pcg.traits.inttype = I
    pcg.traits.veclen = N
	pcg.traits.range = 32

	terra pcg:random_integer()
		var oldstate = self.state
		self.state = (
			oldstate * [uint64](6364136223846793005ull) + (self.inc or 1u)
		)
		var xorshifted: SIMD32 = ((oldstate >> 18u) ^ oldstate) >> 27u
		var rot: SIMD32 = oldstate >> 59u
		return (xorshifted >> rot) or (xorshifted << ((-rot) and 31))
	end

    local terra cast(x: &vector(I, N))
        return escape
            local arg = terralib.newlist()
            for i = 1, N do
                arg:insert(`(@x)[i - 1])
            end
            emit `vectorof(F, [arg])
        end
    end

    terra pcg:random_uniform()
        var x = self:random_integer()
        return cast(&x) / [F](4294967296.) -- = 2^32
    end

    terra pcg:random_normal(mean: SIMD, variance: SIMD)
        var u1 = self:random_uniform()
        var u2 = self:random_uniform()
        var radius = vecmath.sqrt(2 * vecmath.log(1 / u1))
        var theta = 2 * [F](tmath.pi) * u2
        return mean + variance * radius * vecmath.cos(theta)
    end

    terra pcg:random_exponential(frequency: SIMD)
        var u = self:random_uniform()
        return -vecmath.log(u) / frequency
    end

	local Integer = concepts.Integer
	terraform pcg.staticmethods.new(
		seed: J1, offset: J2
	) where {J1: Integer, J2: Integer}
        var stream = escape
            local arg = terralib.newlist()
            for i = 1, N do
                arg:insert(quote in offset + i - 1 end)
            end
            emit `vectorof(uint64, [arg])
        end
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

return {
    VectorPCG = VectorPCG,
}

