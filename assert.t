-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local C = terralib.includecstring [[
    #include <stdio.h>
    #include <stdlib.h>
]]

local ffi = require("ffi")
local OS = ffi.os

local S = {}

S.error = macro(function(expr, msg)
    local tree = expr.tree
    local filename = tree.filename
    local linenumber = tree.linenumber
    local offset = tree.offset
    local loc = filename .. ":" .. linenumber .. "+" .. offset
    return quote
        terralib.debuginfo(filename, linenumber)
        C.printf("%s: %s\n", loc, msg)
        escape
            --traceback currently does not work on macos
            if OS == "Linux" then
                emit quote terralib.traceback(nil) end
            end
        end
        C.abort()
    end
end)

S.assert = macro(function(condition)
    return quote
        if not condition then
            S.error(condition, "assertion failed!")
        end
    end
end)

return S

