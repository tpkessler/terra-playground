-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

require("terralibext")

local alloc = require("alloc")
local sarray = require("sarray")
local darray = require("darray")
local sparse = require("sparse")
local tmath = require("tmath")
local range = require("range")
local random = require("random")

local io = terralib.includec("stdio.h")

local size_t = int64
local T = double
local random_generator = random.MinimalPCG(T)

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



local DefaultAlloc = alloc.DefaultAllocator()
local svecd5 = sarray.StaticVector(T, 5)
local CSR = sparse.CSRMatrix(T, size_t)

local geometry_particulars = function(x, y, h)

    ---------------------------
    --dependent parameters
    ---------------------------
    assert(#x == 4 and #y == 3)
    local m, n = 0, 0 -- mesh dimensions
    local mm, nn = terralib.newlist(), terralib.newlist()
    for i = 1, 3 do
        mm[i] = (x[i+1] - x[i]) / h
        m = m + mm[i]
        assert(math.isinteger(mm[i]), 
            "Cellsize needs to be chosen such that number of cells are integral.")
    end
    for j = 1, 2 do
        nn[j] = (y[j+1] - y[j]) / h
        n = n + nn[j]
        assert(math.isinteger(nn[j]), 
            "Cellsize needs to be chosen such that number of cells are integral.")
    end

    --total number of cells, including ghost-cells that are not part of the computation
    local n_total_cells = m * n
    local n_actice_cells = n_total_cells - mm[2] * nn[2]

    --structure that holds all geometric particulars
    local struct geomp{
        x : T[4]
        y : T[3]
        h : T
        dim : size_t[2]
        active : bool[n_total_cells]
        rand : random_generator
    }

    terra geomp:multiindex(k : size_t) : {size_t, size_t}
        return k % self.dim[0], k / self.dim[0]
    end

    terra geomp:lindex(i : size_t, j : size_t) : size_t
        return i + self.dim[0]*j
    end

    terra geomp:position(i : size_t, j : size_t, u : T, v : T) : {T, T}
        return self.x[0] + (i+u) * h, self.y[0] + (j+v) * h
    end

    terra geomp:__init()
        --------xcoords------
        self.x[0] = [ x[1] ]
        self.x[1] = [ x[2] ]
        self.x[2] = [ x[3] ]
        self.x[3] = [ x[4] ]
        --------ycoords------
        self.y[0] = [ y[1] ]
        self.y[1] = [ y[2] ]
        self.y[2] = [ y[3] ]
        ------mesh size------
        self.h = h
        ---mesh dimensions---
        self.dim[0] = m
        self.dim[1] = n
        --set active cells
        var k = 0
        for j = 0, n do
            for i = 0, m do
                var c = self:position(i, j, 0.5, 0.5) --compute cell-center
                if (self.x[1] < c._0 and c._0 < self.x[2]) and (self.y[1] < c._1 and c._1 < self.y[2]) then
                    self.active[k] = false
                else
                    self.active[k] = true
                end
                k = k + 1
            end
        end
        --initialize random number generator
        self.rand = random_generator.new(238904)
    end

    terra geomp:random_uniform_position(i : size_t, j : size_t)
        --uniformly sampled random variables between 0 and 1
        var u = self.rand:random_uniform()
        var v = self.rand:random_uniform()
        --randomly sampled velocity
        return self:position(i, j, u, v) 
    end

    return geomp
end


import "terratest/terratest"


testenv "DSMC - geometry" do

    local h = 1

    terracode
        var i : size_t[4]
        var j : size_t[4]
        var x : T[5]
        var y : T[5]
        var geo : geometry_particulars({-5, -3, 2, 3}, {0,1,3}, h)
    end

    test geo.dim[0] == 8
    test geo.dim[1] == 3

    testset "multi-indices" do
        terracode
            i[0], j[0] = geo:multiindex(0)
            i[1], j[1] = geo:multiindex(5)
            i[2], j[2] = geo:multiindex(10)
            i[3], j[3] = geo:multiindex(21)
        end
        test i[0]==0 and j[0]==0
        test i[1]==5 and j[1]==0
        test i[2]==2 and j[2]==1
        test i[3]==5 and j[3]==2
    end

    testset "particle position" do
        terracode
            x[0], y[0] = geo:position(4, 2, 0.0, 0.0)
            x[1], y[1] = geo:position(4, 2, 1.0, 0.0)
            x[2], y[2] = geo:position(4, 2, 1.0, 1.0)
            x[3], y[3] = geo:position(4, 2, 0.0, 1.0)
            x[4], y[4] = geo:position(4, 2, 0.5, 0.5)
        end
        test x[0]==-1   and y[0]==2
        test x[1]== 0   and y[1]==2
        test x[2]== 0   and y[2]==3
        test x[3]==-1   and y[3]==3
        test x[4]==-0.5 and y[4]==2.5
    end

    testset "particle random position" do
        terracode
            var xx, yy = T(0), T(0)
            var m = 100000
            for k = 1, m do
                var t = geo:random_uniform_position(4, 2)
                xx = xx + t._0
                yy = yy + t._1
            end
            xx = xx / m
            yy = yy / m
            var xref, yref = geo:position(4, 2, 0.5, 0.5)
        end
        test tmath.isapprox(xx, xref, 1e-3)
        test tmath.isapprox(yy, yref, 1e-3)
    end

    testset "active cells" do
        --left reservoir
        for j = 0, 2 do
            for i = 0, 1 do
                k = i + 8 * j
                test geo.active[k] == true
            end
        end
        --channel
        for j = 0, 0 do
            for i = 2, 6 do
                k = i + 8 * j
                test geo.active[k] == true
            end
        end
        --above channel
        for j = 1, 2 do
            for i = 2, 6 do
                k = i + 8 * j
                test geo.active[k] == false
            end
        end
        --right reservoir
        for j = 0, 2 do
            for i = 7, 7 do
                k = i + 8 * j
                test geo.active[k] == true
            end
        end
    end
end

--[[
terra main()
    var alloc: DefaultAlloc
    var i, j = multiindex(0)
    var x, y = position(i, j, 0, 0)
    io.printf("i, j = %d, %d\n", i, j)
    io.printf("x, y = %0.3f, %0.3f\n", x, y)
end
print(main())
--]]

