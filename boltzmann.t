import "terraform"

local alloc = require("alloc")
local base = require("base")
local concept = require("concept-new")
local vecbase = require("vector")
local svector = require("svector")
local dvector = require("dvector")
local tmath = require("mathfuns")
local dual = require("dual")
local range = require("range")
local quad = require("gauss")
local thread = setmetatable(
    {C = terralib.includec("pthread.h")},
    {__index = function(self, key)
                   return rawget(self.C, key) or self.C["pthread_" .. key]
                end
    }
)
terralib.linklibrary("libpthread.so.0")
local gsl = terralib.includec("gsl/gsl_integration.h")

local dualDouble = dual.DualNumber(double)


local dvecDouble = dvector.DynamicVector(double)
local struct quad(base.AbstractBase) {
    w: dvecDouble
    x: dvecDouble
}

local Alloc = alloc.Allocator
terra quad.staticmethods.new_hermite(alloc: Alloc, n: int64)
    var t = gsl.gsl_integration_fixed_hermite
    var work = gsl.gsl_integration_fixed_alloc(t, n, 0, 0.5, 0.0, 0.0)
    -- defer gsl.gsl_integration_fixed_free(work)
    -- var w = gsl.gsl_integration_fixed_weights(work)
    -- var x = gsl.gsl_integration_fixed_nodes(work)
    var q: quad
    q.w = dvecDouble.new(alloc, n)
    q.x = dvecDouble.new(alloc, n)
    -- for i = 0, n do
    --     q.w(i) = w[i] / tmath.sqrt(2.0 * math.pi)
    --     q.x(i) = x[i]
    -- end
    return q
end

local Real = concept.Real
local Vector = vecbase.Vector
terraform moments(ntrialv: int64, trial_powers: &int32)
end

terraform halfspace(
    ntestv: int64, test_powers: &int32, rho: T1, u: &V1, theta: T2, normal: &V2
)
    where {T1: Real, V1: Vector, T2: Real, V2: Vector}
    var un = u:dot(normal)
end

local terra outflow(
    num_threads: int64,
    -- Dimension of test space and the result arrays
    ntestx: int64,
    ntextv: int64,
    -- Result of half space integral
    resval: &double,
    restng: &double,
    -- Dimension of trial space and the input arrays
    ntrialx: int64,
    ntrialv: int64,
    -- Evaluation point
    val: &double,
    -- Direction of derivative
    tng: &double,
    -- Number of spatial quadrature points
    nqx: int64,
    -- Spatial dimension
    ndim: int64,
    -- Sampled normals
    normal: &double,
    -- Point evaluation of spatial test functions at quadrature points
    testdata: &double,
    testrow: &int32,
    testcolptr: &int32,
    -- Point evaluation of spatial trial functions at quadrature points
    trialdata: &double,
    trialcol: &int32,
    trialrowptr: &int32,
    -- Monomial powers of polynomial approximation in velocity
    test_powers: &int32,
    trial_powers: &int32
)
end

local DefaultAlloc = alloc.DefaultAllocator()
local io = terralib.includec("stdio.h")
terra main()
    var alloc: DefaultAlloc
    var n = 4
    var q = quad.new_hermite(&alloc, n)
    for wx in range.zip(q.w, q.x) do
        io.printf("%g %g\n", wx._0, wx._1)
    end
end
main()
