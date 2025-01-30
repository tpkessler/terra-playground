-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local sarray = require("sarray")
local darray = require("darray")
local sparse = require("sparse")
local tmath = require("tmath")
local range = require("range")

local io = terralib.includec("stdio.h")

local size_t = int64
local T = double

math.round = function(x)
    return math.floor(x+0.5)
end

math.isinteger = function(x)
    return math.round(x) == x
end

--Reden testcase geometry
-----------------|                             \----------------- 5
--               |                             \               --
--               |                             \               --
--               |-----------------------------\               -- 0.5
----------------------------------------------------------------- 0                   
-- -10           0                             20               30

----------------------------
--characteristic dimensions
----------------------------
local xa = 0
local xb = 10
local xc = 20
-------------
local ya = 0
local yb = 0.5
local yc = 5

---------------------------
--discretization parameters
---------------------------
local h = 0.1   --needs to be chosen such that it fits with the boundaries
--which means that the characteristic dimensions are divisible by this number
local N = 100   --particles per cell
local dt = 1    --timestep for explicit time integration


---------------------------
--dependent parameters
---------------------------
local m_ab = (xb - xa) / h
local m_bc = (xc - xb) / h
local n_ab = (yb - ya) / h
local n_bc = (yc - yb) / h
--total number of cells, including ghost-cells that are not part of the computation
local m = 2 * (m_ab + m_bc)
local n = 2 * (n_ab + n_bc)
local n_total_cells = m * n
local n_actice_cells = 2 * (m_ab * n_ab + m_bc * n_ab + m_bc * n_bc)


assert(math.isinteger(m_ab) and math.isinteger(m_bc) and math.isinteger(n_ab) and math.isinteger(n_bc), 
    "Cellsize needs to be chosen such that number of cells are integral.")

local DefaultAlloc = alloc.DefaultAllocator()
local dvec_i = darray.DynamicVector(size_t)
local svec_b = sarray.StaticVector(bool, n_total_cells)
local CSR = sparse.CSRMatrix(T, size_t)

m = 5
terra multiindex(i : size_t) : size_t
    return i / m
end


--[[
terra init_geometry()
    var active_cells = dvec_i.zeros()
    for i = 0, active_cells:length() do
        active_cells(i) = true
    end
end
--]]

terra main()
    var alloc: DefaultAlloc
    return multiindex(12)
end
print(main())

