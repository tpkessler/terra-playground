-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

-- The complex data type is not understood by terra. Hence we provide our own type.
local C = terralib.includecstring([[
        typedef struct{
            double re;
            double im;
        } terra_complex_double;

        typedef struct{
            float re;
            float im;
        } terra_complex_float;
        
        #include <openblas/lapacke.h>
    ]], {"-Dlapack_complex_float=terra_complex_float",
        "-Dlapack_complex_double=terra_complex_double"})

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
S.COL_MAJOR = C.LAPACK_COL_MAJOR
S.ROW_MAJOR = C.LAPACK_ROW_MAJOR

local type = {
    float, double, complexFloat, complexDouble
}

local lapack_type = {
    float, double, C.terra_complex_float, C.terra_complex_double
}

local function lapack_name(pre, name)
    return string.format("LAPACKE_%s%s", pre, name)
end

-- Return a list of terra functions that comprises the C calls for LAPACK
-- calls of all four supported types.
local function default_lapack(C, name, cname)
    local prefix = terralib.newlist{"s", "d", "c", "z"}
    return prefix:map(function(pre)
                          local c_name = lapack_name(pre, name)
                          -- C namespaces in terra have an overloaded get.
                          -- Use rawget to check if a function (that is key)
                          -- exists.
                          local func = rawget(C, c_name)
                          if func then
                              return C[c_name]
                          else
                              local c_name = lapack_name(pre, cname)
                              return C[c_name]
                          end
                      end)
end


local lapack = {
    --
    -- LU
    --
    -- decomposition
    {"getrf", default_lapack(C, "getrf")},
    -- solve
    {"getrs", default_lapack(C, "getrs")},

    --
    -- Cholesky
    --
    -- decomposition
    {"potrf", default_lapack(C, "potrf")},
    -- solve
    {"potrs", default_lapack(C, "potrs")},

    --
    -- Brunch-Kaufman (LDL^T)
    --
    -- decomposition
    {"sytrf", default_lapack(C, "sytrf")},
    -- solve
    {"sytrs", default_lapack(C, "sytrs")},

    --
    -- Eigenproblem
    --
    -- Symmetric
    {"syev", default_lapack(C, "syev", "heev")},
    -- General
    {"geev", default_lapack(C, "geev")},

    --
    -- Generalized Eigenproblem
    --
    -- symmetric 
    {"sygv", default_lapack(C, "sygv", "hegv")},
    -- general
    {"ggev", default_lapack(C, "ggev")},

    --
    -- QR
    --
    -- decomposition
    {"geqrf", default_lapack(C, "geqrf")},
    -- orthogonal matrix
    {"ormqr", default_lapack(C, "ormqr", "unmqr")},
    -- triangular solve
    {"trtrs", default_lapack(C, "trtrs")},

    --
    -- QR with pivoting
    --
    --decomposition
    {"geqp3", default_lapack(C, "geqp3")},
    -- orthogonal matrix
    -- ormqr, see above
    -- triangular solve
    -- trsm, see blas

    --
    -- SVD
    --
    -- decomposition
    {"gesvd", default_lapack(C, "gesvd")},

    --
    -- Generalized SVD
    --
    -- decomposition
    {"ggsvd", default_lapack(C, "ggsvd")},
}


for _, func in pairs(lapack) do
    local name = func[1]
    local c_func = func[2]
    S[name] = terralib.overloadedfunction(name)
    for i = 1, 4 do
        S[name]:adddefinition(
            wrapper.generate_wrapper(type[i], c_func[i], lapack_type[i])
        )
    end
end

return S
