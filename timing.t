-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concepts = require("concepts")
local time = terralib.includec("time.h")
local omp = terralib.includec("omp.h")
local ffi = require("ffi")
local OS = ffi.os

if OS == "Linux" then
	terralib.linklibrary("libgomp.so")
elseif OS == "Darwin" then
	terralib.linklibrary("libgomp.dylib")
else
	error("Unsupported OS " .. OS)
end

import "terraform"

local Float = concepts.Float
local concept Timer
	terra Self:start() end
	terra Self:stop(): Float end
end

local struct default {
	old: double
}

do
	local now = quote
			var now: time.timespec
			var res = time.clock_gettime(time.CLOCK_REALTIME, &now)
		in
			1.0 * now.tv_sec + 1e-9 * now.tv_nsec
		end

	terra default:start()
		self.old = [now]
	end

	terra default:stop()
		var cur = [now]
		return cur - self.old
	end
end
assert(Timer(default))

local struct omp_timer {
	old: double
}

do
	local now = `omp.omp_get_wtime()
	terra omp_timer:start()
		self.old = [now]
	end

	terra omp_timer:stop()
		var cur = [now]
		return cur - self.old
	end
end
assert(Timer(omp_timer))

return {
	default_timer = default,
	parallel_timer = omp_timer,
	Timer = Timer,
}
