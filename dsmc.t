-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local base = require("base")
local concepts = require("concepts")
local template = require("template")
local random = require("random")
local dvector = require("dvector")
local svector = require("svector")
local vecbase = require("vector")
local random = require("random")
local io = terralib.includec("stdio.h")
local tmath = require("mathfuns")
local err = require("assert")

local ParticleSystem = terralib.memoize(function(T)
    assert(concepts.Real(T))
    local Allocator = alloc.Allocator
    local DVec = dvector.DynamicVector(T)
    local struct particle_system(base.AbstractBase) {
        n: int64
        v: DVec
    }
    particle_system.eltype = T

    particle_system.staticmethods.new = terra(alloc: Allocator, n: int64)
        return particle_system {n, DVec.new(alloc, 3 * n)}
    end

    terra particle_system:size()
        return self.n
    end

    terra particle_system:getvelocities()
        return self.v
    end

    local Vec = vecbase.Vector
    local SVec = svector.StaticVector(T, 3)
    particle_system.templates.collision_transform = template.Template:new("collision_transform")
    particle_system.templates.collision_transform[{&particle_system.Self, &Vec, &Vec, &Vec} -> {}]
    = function(Self, V1, V2, V3)
        local terra impl(self: Self, v: V1, w: V2, e: V3)
            err.assert(v:size() == 3)
            err.assert(w:size() == 3)
            err.assert(e:size() == 3)

            var u = SVec.new()
            u:copy(w)
            u:axpy(T(-1.0), v)

            var scatter = u:dot(e)
            v:axpy(scatter, e)
            w:axpy(-scatter, e)
        end
        return impl
    end

    terra particle_system:max_relative_velocity_bound()
        var mean = SVec.new()
        for j = 0, 3 do
            mean(j) = [T](0)
            for i = 0, self.n do
                mean(j) = self.v(3 * i + j) + i * mean(j)
                mean(j) = mean(j) / (i + 1)
            end
        end
        var umax = [T](-1)
        for i = 0, self.n do
            var u = SVec.new()
            for j = 0, 3 do
                u(j) = self.v(3 * i + j) - mean(j)
            end
            umax = tmath.max(umax, tmath.sqrt(u:dot(&u)))
        end
        return 2 * umax
    end

    terra particle_system:time_counter(umax: T)
        -- The time counter depends on the majorant for the collision kernel.
        -- When using the maximal relative velocity it follows this simple
        -- expression.
        return [T](2) / (umax * (self.n - 1))
    end

    local Rand = random.RandomDistributer(T)

    terra particle_system:jump_time(rand: Rand, umax: T)
        -- As a Markovian jump process, state jumps are exponentially
        -- distributed.
        var tau = self:time_counter(umax)
        return rand:rand_exp(1 / tau)
    end

    local terra rand_sphere(rand: Rand, e: &SVec)
        -- To uniformly sample from the sphere we first sample from an
        -- isotropic normal distribution in 3D and then normalize the result
        -- to unit length.
        for i = 0, 3 do
            e(i) = rand:rand_normal([T](0), [T](1))
        end
        var nrm = tmath.sqrt(e:dot(e))
        e:scal(1 / nrm)
    end

    terra particle_system:collide(rand: Rand, dt: T)
        -- For a list of collision processes, see
        -- Rjasanow, Wagner: On time counting procedures in the DSMC method for rarefied gases,
        -- https://doi.org/10.1016/S0378-4754(98)00142-6

        -- Compute an upper bound for the largest relative velocity in the gas
        var umax = self:max_relative_velocity_bound()
        var t = [T](0)
        var v = SVec.new()
        var w = SVec.new()
        var u = SVec.new()
        var e = SVec.new()
        -- Time step size is really just observation time of a Markovian
        -- process.
        -- For the 0d Boltzmann equation, DSMC doesn't introduce a time
        -- discretization.
        while t < dt do
            -- Sample collision partners
            var i: int64 = self. n * rand:rand_uniform()
            var j: int64
            repeat
                j = self. n * rand:rand_uniform()
            until i ~= j

            -- Compute hard sphere collision kernel for sampled particles
            var unrm = [T](0)
            for k = 0, 3 do
                var diff = self.v(3 * i + k) - self.v(3 * j + k)
                unrm = unrm + diff * diff
            end
            unrm = tmath.sqrt(unrm)

            -- Rejection sampling.
            -- Since we sampled the collision partners from a uniform
            -- distribution we can only accept those that follow the real
            -- distribution according to the collision kernel.
            if rand:rand_uniform() < unrm / umax then
                -- If accepted, sample a scattering direction.
                -- For hard spheres, it is uniformly distributed on the unit
                -- sphere.
                rand_sphere(rand, &e)

                for k = 0, 3 do
                    v(k) = self.v(3 * i + k)
                    w(k) = self.v(3 * j + k)
                end
                self:collision_transform(&v, &w, &e)
                for k = 0, 3 do
                    self.v(3 * i + k) = v(k)
                    self.v(3 * j + k) = w(k)
                end
            end
            -- A collision has an exponentially distributed probability to
            -- happen within a certain time.
            -- Hence, each collision increases our observation time.
            t = t + self:jump_time(rand, umax)
        end
    end

    terra particle_system:maxwellian(rand: Rand, u: &SVec, theta: T)
        for i = 0, self.n do
            for j = 0, 3 do
                self.v(3 * i + j) = rand:rand_normal(u(j), tmath.sqrt(theta))
            end
        end
    end

    terra particle_system:mixture(rand: Rand, alpha: T,
                                  u1: &SVec, theta1: T,
                                  u2: &SVec, theta2: T)
        for i = 0, self.n do
            for j = 0, 3 do
                if rand:rand_uniform() < alpha then
                    self.v(3 * i + j)
                        = rand:rand_normal(u1(j), tmath.sqrt(theta1))
                else
                    self.v(3 * i + j)
                        = rand:rand_normal(u2(j), tmath.sqrt(theta2))
                end
            end
        end
    end

    return particle_system
end)

local ParticleSystem = ParticleSystem(double)
local SVec = svector.StaticVector(double, 3)
local DefaultAllocator = alloc.DefaultAllocator()
local Rand = random.MinimalPCG(double)
terra main()
    var rand = Rand.from()
    var alloc: DefaultAllocator
    var n = [int64](1e5)
    var tend = 10.0
    var dt = 1e-1
    var nt = [int64](tend / dt)
    var p = ParticleSystem.new(&alloc, n)
    var u1 = SVec.zeros()
    u1(0) = -3.0
    var u2 = SVec.zeros()
    u2(0) = 3.0
    var theta = 1.0
    p:mixture(&rand, 0.5, &u1, theta, &u2, theta)
    -- Time stepping is only necessary if intermediate values of the particle
    -- density function are wanted.
    for i = 0, nt do
        p:collide(&rand, dt)
    end
    for i = 0, n  do
        io.printf("%.7e %.7e %.7e\n",
                  p.v(3 * i), p.v(3 * i + 1), p.v(3 * i + 2))
    end
end

main()
