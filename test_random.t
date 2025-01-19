-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local random = require("random")

import "terratest/terratest"

for _, GEN in pairs{random.LibC, random.KISS, random.MinimalPCG, random.PCG} do
	for _, T in pairs{float, double} do
		local RNG = GEN(T)
		testenv(RNG) "PRNG" do
			testset "New" do
				terracode
					var rng = RNG.new(238904)
					escape
						test [rng.type == RNG]
					end
				end
			end

			testset "Seed" do
				local N = 11
				terracode
					var seed = 23478
					var x: int64[N]
					do
						var rng = RNG.new(seed)
						for i = 0, N do
							x[i] = rng:random_integer()
						end
					end
					var y: int64[N]
					do
						var rng = RNG.new(seed)
						for i = 0, N do
							y[i] = rng:random_integer()
						end
					end
				end

				local io = terralib.includec("stdio.h")
				for i = 0, N - 1 do
					test x[i] == y[i]
				end
			end
		end
	end
end
