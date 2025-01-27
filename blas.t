-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local C = terralib.includecstring[[
    #include <openblas/cblas.h>
]]

local uname = io.popen("uname", "r"):read("*a")
if uname == "Darwin\n" then
    terralib.linklibrary("libopenblas.dylib")
elseif uname == "Linux\n" then
    terralib.linklibrary("libopenblas.so")
else
    error("Not implemented for this OS.")
end

local complex = require("complex")

local complexFloat = complex.complex(float)
local complexDouble = complex.complex(double)

local wrapper = require("wrapper")

local S = {}
S.RowMajor = C.CblasRowMajor
S.ColMajor = C.CblasColMajor

S.NoTrans = C.CblasNoTrans
S.Trans = C.CblasTrans
S.ConjTrans = C.CblasConjTrans

S.Upper = C.CblasUpper
S.Lower = C.CblasLower

S.Left = C.CblasLeft
S.Right = C.CblasRight

S.Unit = C.CblasUnit
S.NonUnit = C.CblasNonUnit

-- All tables follow this ordering
local type = {
    float, double, complexFloat, complexDouble
}

local function blas_name(pre, name)
    return string.format("cblas_%s%s", pre, name)
end

local function default_blas(C, name, alt_name)
    alt_name = alt_name or name
    local prefix = terralib.newlist{"s", "d", "c", "z"}
    return prefix:map(function(pre)
                          local c_name = blas_name(pre, name)
                          if not rawget(C, c_name) then
                              c_name = blas_name(pre, alt_name)
                          end
                          return C[c_name]
                      end)
end

local blas = {
    -- BLAS level 1
    {"swap", default_blas(C, "swap")},
    {"scal", default_blas(C, "scal")},
    {"copy", default_blas(C, "copy")},
    {"axpy", default_blas(C, "axpy")},
    {"dot",  default_blas(C, "dot", "dotc_sub")},
    {"nrm2", {C.cblas_snrm2, C.cblas_dnrm2, C.cblas_scnrm2, C.cblas_dznrm2}},
    {"asum", {C.cblas_sasum, C.cblas_dasum, C.cblas_scasum, C.cblas_dzasum}},
    {"iamax", {C.cblas_isamax, C.cblas_idamax, C.cblas_icamax, C.cblas_izamax}},

    -- BLAS level 2
    {"gemv", default_blas(C, "gemv")},
    {"trsv", default_blas(C, "trsv")},
    {"trmv", default_blas(C, "trmv")},

    -- BLAS level 3
    {"gemm", default_blas(C, "gemm")},
    {"trsm", default_blas(C, "trsm")},
}

for _, func in pairs(blas) do
    local name = func[1]
    local c_func = func[2]
    S[name] = terralib.overloadedfunction(name)
    for i = 1, 4 do
        -- Use float implementation as reference for function signature
        S[name]:adddefinition(
            wrapper.generate_wrapper(type[i], c_func[i], type[1], c_func[1])
        )
    end
end

return S
