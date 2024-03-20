local random = require("random")
local C = terralib.includec("stdio.h")

terra main()
	escape
		for _, name in ipairs({"Default", "PCG", "MinimalPCG", "KISS", "TinyMT"}) do
			local gen = random[name]
			local rand = gen(double)
			emit quote
				var rng = [rand].from()
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

