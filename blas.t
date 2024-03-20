local C = terralib.includecstring[[
    #include <openblas/cblas.h>
]]
terralib.linklibrary("libcblas.so")

local complex = require("complex")

local complexFloat = complex(float)[1]
local complexDouble = complex(double)[1]

local blas_parser = require("blas_parser")

local S = {}
S.RowMajor = C.CblasRowMajor
S.ColMajor = C.CblasColMajor

S.NoTrans = C.CblasNoTrans
S.Trans = C.CblasTrans
S.ConjTrans = C.CblasConjTrans

S.Upper = C.CblasUpper
S.Lower = C.CblasLower

S.Unit = C.CblasUnit
S.NonUnit = C.CblasNonUnit

local default_types = {
    ["s"] = float,
    ["d"] = double,
    ["c"] = complexFloat,
    ["z"] = complexDouble}

local dot_suffix = {
    ["c"] = "c_sub",
    ["z"] = "c_sub"}

local ger_suffix = {
    ["c"] = "c",
    ["z"] = "c"}

local nrm_types = {
    ["s"] = float,
    ["d"] = double,
    ["sc"] = complexFloat,
    ["dz"] = complexDouble}

local blas = {
    -- BLAS 1
    {"%sswap", default_types, {},
        {"integer", "scalar_array", "integer", "scalar_array", "integer"}, {}},
    {"%sscal", default_types, {},
        {"integer", "scalar", "scalar_array", "integer"}, {}},
    {"%scopy", default_types, {},
        {"integer", "scalar_array", "integer", "scalar_array", "integer"}, {}},
    {"%saxpy", default_types, {},
        {"integer", "scalar", "scalar_array", "integer", "scalar_array", "integer"}, {}},
    {"%sdot%s", default_types, dot_suffix,
        {"integer", "scalar_array", "integer", "scalar_array", "integer"}, {"scalar"}},
    {"%snrm2", nrm_types, {},
        {"integer", "scalar_array", "integer"}, {"real_scalar"}},
    {"%sasum", nrm_types, {},
        {"integer", "scalar_array", "integer"}, {"real_scalar"}},
    {"i%samax", default_types, {},
        {"integer", "scalar_array", "integer"}, {"integer"}},
    -- BLAS 2
    {"%sgemv", default_types, {},
        {"integer", "integer", "integer", "integer", "scalar", "scalar_array",
         "integer", "scalar_array", "integer", "scalar", "scalar_array", "integer"}, {}},
    {"%sger%s", default_types, ger_suffix,
        {"integer", "integer", "integer", "scalar", "scalar_array", "integer",
         "scalar_array", "integer", "scalar_array", "integer"}, {}},
    {"%strsv", default_types, {},
        {"integer", "integer", "integer", "integer", "integer", "scalar_array", "integer",
         "scalar_array", "integer"}, {}},
    -- BLAS 3
    {"%sgemm", default_types, {},
        {"integer", "integer", "integer", "integer", "integer", "integer",
         "scalar", "scalar_array", "integer", "scalar_array", "integer",
         "scalar", "scalar_array", "integer"}, {}}
}

for _, func in pairs(blas) do
    local name = string.format(func[1], "", "")
    S[name] = blas_parser.factory(unpack(func))
end

return S
