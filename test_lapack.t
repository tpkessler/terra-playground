local lapack = require("lapack")
local io = terralib.includec("stdio.h")
local complex = require("complex")
local random = require("random")

local complexFloat = complex.complex(float)
local complexDouble = complex.complex(double)

local types = {
    ["s"] = float,
    ["d"] = double,
    ["c"] = complexFloat,
    ["z"] = complexDouble,
}

local unit = {
    ["s"] = `float(0),
    ["d"] = `double(0),
    ["c"] = `complexFloat.I,
    ["z"] = `complexDouble.I,
}

import "terratest/terratest"

for prefix, T in pairs(types) do
    local I = unit[prefix]
    testenv(T) "LU decomposition" do

    end
end --for type
