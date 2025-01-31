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

import "terraform"
local io = terralib.includec("stdio.h")

local size_t = int64
local T = double
local random_generator = random.MinimalPCG(T)
local Allocator = alloc.Allocator

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



local DefaultAllocator = alloc.DefaultAllocator()
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
    local n_active_cells = n_total_cells - mm[2] * nn[2]



    --structure that holds all geometric particulars
    local S = T[4]
    local struct geomp{
        grid : S[2]
        h : T
        dim : size_t[2]
        active : bool[n_total_cells]
        rand : random_generator
    }

    terra geomp:n_total_cells()
        return n_total_cells
    end

    terra geomp:n_active_cells()
        return n_active_cells
    end

    terra geomp:multiindex(k : size_t) : {size_t, size_t}
        return k % self.dim[0], k / self.dim[0]
    end

    terra geomp:lindex(i : size_t, j : size_t) : size_t
        return i + self.dim[0]*j
    end

    terra geomp:coordinate(coordinate : size_t, i : size_t, u : T) : T
        return self.grid[coordinate][0] + (i + u) * h
    end

    terra geomp:position(i : size_t, j : size_t, u : T, v : T) : {T, T}
        return self.grid[0][0] + (i+u) * h, self.grid[1][0] + (j+v) * h
    end

    terra geomp:__init()
        --------x-coords------
        self.grid[0][0] = [ x[1] ]
        self.grid[0][1] = [ x[2] ]
        self.grid[0][2] = [ x[3] ]
        self.grid[0][3] = [ x[4] ]
        --------y-coords------
        self.grid[1][0] = [ y[1] ]
        self.grid[1][1] = [ y[2] ]
        self.grid[1][2] = [ y[3] ]
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
                if (self.grid[0][1] < c._0 and c._0 < self.grid[0][2]) and (self.grid[1][1] < c._1 and c._1 < self.grid[1][2]) then
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

    terra geomp:random_coordinate(coordinate : size_t, i : size_t) : T
        return self:coordinate(coordinate, i, self.rand:random_uniform())
    end

    terra geomp:random_velocity(mean : T, variance : T) : T
        return self.rand:random_normal(mean, variance)
    end

    terra geomp:random_normal_velocity(mean : T, temperature : T)
        --normaly distributed velocities with temperature and mean
        var variance = tmath.sqrt(temperature)
        return self.rand:random_normal(mean, variance), self.rand:random_normal(mean, variance)
    end

    --for range over active cells
    geomp.metamethods.__for = function(self, body)
        return quote
            for cellid = 0, n_total_cells do  
                if self.active[cellid] then
                    [body(cellid)]
                end
            end
        end
    end

    return geomp
end


local h = 0.5
local N = 2
local dt = 1.0
local safetyfactor = 1
local temperature = 1.0

local simdsize = 64
local SIMD_T = vector(T, simdsize)
local SIMD_I = vector(size_t, simdsize)
local SIMD_B = vector(bool, simdsize)

local dvec = darray.DynamicVector(T)
local dvec_i = darray.DynamicVector(size_t)
local dvec_b = darray.DynamicVector(bool)

local terra round_to_aligned(size : size_t, alignment : size_t) : size_t
    return  ((size + alignment - 1) / alignment) * alignment
end

local struct particle_distribution{
    position : tuple(dvec, dvec)                --x- and y-coordinate 
    velocity : tuple(dvec, dvec, dvec)          --x- and y- and z-velocity component
    cellid   : tuple(dvec_i, dvec_i, dvec_i)    --i- and j- multiindices and k- linear indices
    mask     : dvec_b                           --used to mask the boundary, etc
    size     : size_t
}

local terraform initial_condition(geo : &G, allocator : &A, n_tot_particles : size_t) where {G, A}
    --create a new uniinitialized particle distribution
    var particle : particle_distribution
    --create vectors for positions and velocities and cell-id
    --position
    particle.position._0 = dvec.zeros(allocator, n_tot_particles)
    particle.position._1 = dvec.zeros(allocator, n_tot_particles)
    --velocities
    particle.velocity._0 = dvec.zeros(allocator, n_tot_particles)
    particle.velocity._1 = dvec.zeros(allocator, n_tot_particles)
    particle.velocity._2 = dvec.zeros(allocator, n_tot_particles)
    --unused particles have cell-id = -1
    particle.cellid._0 = dvec_i.all(allocator, n_tot_particles, -1)
    particle.cellid._1 = dvec_i.all(allocator, n_tot_particles, -1)
    particle.cellid._2 = dvec_i.all(allocator, n_tot_particles, -1)
    --create a mask
    particle.mask = dvec_b.all(allocator, n_tot_particles, false)
    --initialize dynamic vectors
    --loop over cells
    var particle_id = 0
    for cell = 0, geo:n_total_cells() do
        --only perform operations for active cells
        if geo.active[cell] then
            --create N particles per cell
            for k = 0, N do
                var mi = geo:multiindex(cell)
                --assign positions
                particle.position._0(particle_id) = geo:random_coordinate(0, mi._0)
                particle.position._1(particle_id) = geo:random_coordinate(1, mi._1)
                --assign velocities
                var variance = tmath.sqrt(T(temperature))
                particle.velocity._0(particle_id) = geo:random_velocity(1, variance)
                particle.velocity._1(particle_id) = geo:random_velocity(1, variance)
                particle.velocity._2(particle_id) = geo:random_velocity(1, variance)
                --assign cell-id
                particle.cellid._0(particle_id) = mi._0
                particle.cellid._1(particle_id) = mi._1
                particle.cellid._2(particle_id) = cell
                --increase particle id
                particle_id = particle_id + 1
            end
        end
    end
    particle.size = particle_id
    return particle
end

local terra linearindex(i : &SIMD_I, j : &SIMD_I, I : &SIMD_I, m : size_t, M : size_t)
    for k = 0, M do
        --vectorized update
        @I = @i + m * @j
        --increment references
        I = I + 1
        i = i + 1
        j = j + 1
    end
end

local terra coordinate_to_index(i : &SIMD_I, x : &SIMD_T, a : T, c : T, M : size_t)
    for k = 0, M do
        --vectorized update
        @i = c * (@x - a)
        --increment references
        x = x + 1
        i = i + 1
    end
end

local terra advect_particles_component(x : &SIMD_T, v : &SIMD_T, M : size_t)
    for k = 0, M do
        --vectorized update
        @x = @x + @v * dt
        --increment references
        x = x + 1
        v = v + 1
    end
end

local terraform cell_index_update(geo : &G, particle : &P) where {G, P}
    coordinate_to_index(
        [&SIMD_I](&particle.cellid._0(0)), 
        [&SIMD_T](&particle.position._0(0)),
        geo.grid[0][0],
        1.0 / h,
        particle.size / simdsize
    )
    coordinate_to_index(
        [&SIMD_I](&particle.cellid._1(0)), 
        [&SIMD_T](&particle.position._1(0)),
        geo.grid[1][0],
        1.0 / h,
        particle.size / simdsize
    )
    linearindex(
        [&SIMD_I](&particle.cellid._0(0)), 
        [&SIMD_I](&particle.cellid._1(0)), 
        [&SIMD_I](&particle.cellid._2(0)), 
        geo.dim[0], 
        particle.size / simdsize
    )
end

local terraform advect_particles(geo : &G, particle : &P) where {G, P}
    advect_particles_component(
        [&SIMD_T](&particle.position._0(0)), 
        [&SIMD_T](&particle.velocity._0(0)), 
        particle.size / simdsize
    )
    advect_particles_component(
        [&SIMD_T](&particle.position._1(0)), 
        [&SIMD_T](&particle.velocity._1(0)), 
        particle.size / simdsize
    )
end

local terra mask_interior(mask : &SIMD_B, x : &SIMD_T, y : &SIMD_T, X : T[4], Y : T[4], M : size_t)
    for k = 0, M do
        --vectorized update
        @mask = 
            (@x > X[0] and @x < X[3]) and (@y > Y[0] and @y < Y[2]) 
                and not (@x > X[1] and @x < X[2]) and  (@y > Y[1] and @y < Y[2])
        --increment references
        mask = mask + 1
        x = x + 1
        y = y + 1
    end
end

local terraform mask_interior_particles(geo : &G, particle : &P) where {G, P}
    mask_interior(
        [&SIMD_B](&particle.mask(0)),
        [&SIMD_T](&particle.position._0(0)),
        [&SIMD_T](&particle.position._1(0)),
        geo.grid[0], 
        geo.grid[1],
        particle.size / simdsize
    )
end

terra main()
    --setup geometic particulars of Reden testcase
    var geo : geometry_particulars({-20, -10, 10, 20}, {0,0.5,5}, h)
    --get the default allocator
    var allocator : DefaultAllocator
    --total available particles, taking care of a safetyfactor
    var n_tot_particles = round_to_aligned(geo:n_active_cells() * N * safetyfactor, simdsize)
    --compute initial phase-space distribution
    var particle = initial_condition(&geo, &allocator, n_tot_particles)
    --perform advection step
    advect_particles(&geo, &particle)
    --update cell coordinates
    cell_index_update(&geo, &particle)
    --create a mask for the interior particles, marking the particles
    --that have left the domain
    mask_interior_particles(&geo, &particle)

    return n_tot_particles
end
print(main())









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
            var m = 1000000
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

    testset "particle random velocity" do
        terracode
            var vv, ww, ss, rr = T(0), T(0), T(0), T(0)
            var m = 1000000
            var V, Tmp = 1.0, 2.0
            for k = 1, m do
                var v = geo:random_normal_velocity(V, Tmp)
                vv = vv + v._0
                ww = ww + v._1
                ss = ss + (v._0 - V) * (v._0 - V)
                rr = rr + (v._1 - V) * (v._1 - V)
            end
            vv = vv / m
            ww = ww / m
            rr = rr / m
            ss = ss / m
        end
        test tmath.isapprox(vv, V, 1e-2)
        test tmath.isapprox(ww, V, 1e-2)
        test tmath.isapprox(rr, Tmp, 1e-2)
        test tmath.isapprox(ss, Tmp, 1e-2)
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