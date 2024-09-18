-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local time = terralib.includec("time.h")
local omp = terralib.includec("omp.h")

local timer = function()
	local struct timer{
		old: double
	}

	local function now()
		return quote
				var now: time.timespec
				var res = time.clock_gettime(time.CLOCK_REALTIME, &now)
			in
				1.0 * now.tv_sec + 1e-9 * now.tv_nsec
		end
				
	end

	terra timer:start()
		self.old = [now()]
	end

	terra timer:stop(): double
		var cur = [now()]
		return cur - self.old
	end

	local S = {}
	S.type = timer
	S.new = macro(function()
		return quote
				var sw: timer
			in
				sw
		end
	end)

	return S
end

local omp = function()
	local struct timer{
		old: double
	}

	local function now()
		return `omp.omp_get_wtime()
	end

	terra timer:start()
		self.old = [now()]
	end

	terra timer:stop(): double
		var cur = [now()]
		return cur - self.old
	end

	local S = {}
	S.type = timer
	S.new = macro(function()
		return quote
			var sw: timer
		in
			sw
		end
	end)

	return S
end

local default_timer = timer()
local omp_timer = omp()

return {default_timer = default_timer, parallel_timer = omp_timer}
