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
terralib.linklibrary("liblapack.so")
terralib.linklibrary("libcblas.so")

local complex = require("complex")

local complexFloat = complex(float)[1]
local complexDouble = complex(double)[1]

local wrapper = require("wrapper")

local S = {}
S.COL_MAJOR = C.LAPACK_COL_MAJOR
S.ROW_MAJOR = C.LAPACK_ROW_MAJOR

local type = {
    float, double, complexFloat, complexDouble
}

local function default_lapack(C, name)
    local prefix = terralib.newlist{"s", "d", "c", "z"}
    return prefix:map(function(pre)
                          local c_name = string.format("LAPACKE_%s%s", pre, name)
                          return C[c_name]
                      end)
end


local lapack = {
    {"geqrf", default_lapack(C, "geqrf")}
}


for _, func in pairs(lapack) do
    local name = func[1]
    local c_func = func[2]
    S[name] = terralib.overloadedfunction(name)
    for i = 1, 4 do
        S[name]:adddefinition(
            wrapper.generate_terra_wrapper(type[i], c_func[i], type[1], c_func[1])
        )
    end
end

return S
