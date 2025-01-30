-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

require("terralibext")

local C = terralib.includecstring[[
    #include <stdio.h>
    #include <unistd.h>
    #include "gnuplot/src/gnuplot_i.h"
]]

local uname = io.popen("uname", "r"):read("*a")
if uname == "Darwin\n" then
	terralib.linklibrary("./gnuplot_i.dylib")
elseif uname == "Linux\n" then
	terralib.linklibrary("./gnuplot_i.so")
else
	error("OS Unknown")
end

local gnuplot = {}

for name, definition in pairs(C) do
    if string.sub(name, 1, 8) == "gnuplot_" then
        local newname = string.sub(name, 9, -1)
        gnuplot[newname] = definition
    end
end


local struct fighandle{
    h : &C.gnuplot_ctrl
}

terra fighandle:__init()
    self.h = C.gnuplot_init()   --fighandle to the window
end

terra fighandle:__dtor()
    C.getchar()                 --wait for user input before closing figure
    C.gnuplot_close(self.h)
end

function fighandle.metamethods.__cast(from, to , exp)
    if from == fighandle and to == &C.gnuplot_ctrl then
        return `exp.h
    else
        error("CompileError: not a valid cast from " .. tostring(from) .. " to " .. tostring(to) .. ".")
    end
end


gnuplot.handle = fighandle

return gnuplot