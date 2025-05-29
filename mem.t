-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local S = {}

local C = terralib.includecstring[[
    #include <stdio.h>
    #include <stdlib.h>
]]

S.new = terra(size: uint64)
    var alignment = 64 -- Memory alignment for AVX512    
    var ptr: &opaque = nil 
    var res = C.posix_memalign(&ptr, alignment, size)

    if res ~= 0 then
        C.fprintf(C.stderr, "Cannot allocate memory for buffer of size %g GiB\n", 1.0 * size / 1024 / 1024 / 1024)
        C.abort()
    end

    return ptr
end

S.del = terra(ptr: &opaque)
    C.free(ptr)
end

return S
