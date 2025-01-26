-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest/terratest"

if not __silent__ then

	local time = require("timing")
	local uni = terralib.includec("unistd.h")
	local io = terralib.includec("stdio.h")

	terra main()
		var sw : time.default_timer
		sw:start()
		uni.usleep(2124)
		var t = sw:stop()
		io.printf("Sleep took %g s\n", t)
	end
	main()

end
