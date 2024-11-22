-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local random = require("random")
local C = terralib.includec("stdio.h")

import "terratest/terratest"

if not __silent__ then

	terra main()
		escape
			for _, name in ipairs({"Default", "PCG", "MinimalPCG", "KISS", "TinyMT"}) do
				local gen = random[name]
				local rand = gen(double)
				emit quote
					var rng = [rand].from(1515151)
					var n: int64 = 2000001
					var mean: double = 0
					for i: int64 = 0, n do
						var u = rng:rand_uniform()
						mean = i * mean + u
						mean = mean / (i + 1)
					end
					C.printf("%s %u %g\n", name, n, mean)
				end
			end
		end
	end

	main()

end

