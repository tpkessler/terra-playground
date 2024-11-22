-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT


local C = terralib.includecstring([[
    #include <stdio.h>
]])
import "terratest"

terra set(p: &double)
    @p = 1.0
end

testenv "pointer" do
    terracode
        var x = 0.0
    end

    testset "pointer set value" do
	terracode
	    set(&x)
	end
        test x == 1.0
    end

    testset "pointer is reset in every testset" do
	test x == 0.0
    end
end
