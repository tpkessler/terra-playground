-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local time = require("timing")
local uni = terralib.includec("unistd.h")
local io = terralib.includec("stdio.h")
terralib.linklibrary("libgomp.so")

terra main()
	var sw = time.default_timer.new()
	sw:start()
	uni.usleep(5e3)
	var t = sw:stop()
	io.printf("Sleep took %g s\n", t)
end
main()
