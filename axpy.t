local C = terralib.includecstring[[
    #include <openblas/cblas.h>
]]
terralib.linklibrary("libcblas.so")

local complex = require("complex")

local complexFloat = complex(float)[1]
local complexDouble = complex(double)[1]

local function has_opaque_interface(prefix)
    if prefix == "c" or prefix == "z" then
        return true
    elseif prefix == "sc" or prefix == "dz" then
        return true
    else
        return false
    end
end

local function generate_blas_args(prefix, T, signature, return_val)
    local terra_arg = terralib.newlist()
    local statements = terralib.newlist()
    local c_arg = terralib.newlist()
    local return_statement = terralib.newlist()

    for _, arg in ipairs(signature) do
        if arg == "integer" then
            local int = symbol(int32)
            terra_arg:insert(int)
            c_arg:insert(int)
        elseif arg == "scalar" then
            local scalar = symbol(T)
            terra_arg:insert(scalar)
            if has_opaque_interface(prefix) then
                local opq = symbol(&opaque)
                c_arg:insert(opq)
                statements:insert(quote
                    var [opq] = [&opaque](&[scalar])
                end)
            else
                c_arg:insert(scalar)
            end
        elseif arg == "scalar_array" then
            local array = symbol(&T)
            terra_arg:insert(array)
            if has_opaque_interface(prefix) then
                local opq = symbol(&opaque)
                c_arg:insert(opq)
                statements:insert(quote
                    var [opq] = [&opaque](array)
                end)
            else
                c_arg:insert(array)
            end
        else
            error("Unknown type " .. arg)
        end -- if arg
    end -- for

    local result = nil
    for _, arg in pairs(return_val) do
        if arg == "real_scalar" then
            local Ts = T.scalar_type and T.scalar_type or T
            result = symbol(Ts)
            return_statement:insert(quote
                return [result]
            end)
        elseif arg == "scalar" then
            local result_cast = symbol(T)
            if has_opaque_interface(prefix) then
                local call_by_ref = symbol(&opaque)
                c_arg:insert(call_by_ref)
                return_statement:insert(quote
                    var [result_cast] = @[&T](call_by_ref)
                end)
            else
                local Ts = T.scalar_type and T.scalar_type or T
                result = symbol(Ts)
            end
            return_statement:insert(quote
                return [result_cast]
            end)
        elseif arg == "integer" then
            result = symbol(int32)
            return_statement:insert(quote
                return [result]
            end)
        else
            error("Unknown type " .. arg)
        end --if arg
    end -- for
    
    return terra_arg, statements, c_arg, result, return_statement
end

local function blas_factory(name, types, signature, return_val)
    local methods = terralib.newlist()
    for prefix, T in pairs(types) do
        local tname = string.format(name, "")
        local pname = string.format(name, prefix)
        local cname = "cblas_" .. pname
        local terra_arg, statements, c_arg, result, return_statement
            = generate_blas_args(prefix, T, signature, return_val)

        local c_call
        if result == nil then
            c_call = `C.[cname]([c_arg])
        else
            c_call = quote var [result] = C.[cname]([c_arg]) end
        end
        local func = terra([terra_arg])
            [statements]
            [c_call]
            [return_statement]
        end
        methods:insert(func)
    end

    return terralib.overloadedfunction(name, methods)
end

local S = {}
S.RowMajor = C.CblasRowMajor
S.ColMajor = C.CblasColMajor

S.NoTrans = C.CblasNoTrans
S.Trans = C.CblasTrans
S.ConjTrans = C.CblasConjTrans

local default_types = {
    ["s"] = float,
    ["d"] = double,
    ["c"] = complexFloat,
    ["z"] = complexDouble}

local nrm_types = {
    ["s"] = float,
    ["d"] = double,
    ["sc"] = complexFloat,
    ["dz"] = complexDouble}

local blas = {
    -- BLAS 1
    {"%sswap", default_types,
        {"integer", "scalar_array", "integer", "scalar_array", "integer"}, {}},
    {"%sscal", default_types,
        {"integer", "scalar", "scalar_array", "integer"}, {}},
    {"%scopy", default_types,
        {"integer", "scalar_array", "integer", "scalar_array", "integer"}, {}},
    {"%saxpy", default_types,
        {"integer", "scalar", "scalar_array", "integer", "scalar_array", "integer"}, {}},
    {"%snrm2", nrm_types,
        {"integer", "scalar_array", "integer"}, {"real_scalar"}},
    {"%sasum", nrm_types,
        {"integer", "scalar_array", "integer"}, {"real_scalar"}},
    {"i%samax", default_types,
        {"integer", "scalar_array", "integer"}, {"integer"}},
    -- BLAS 2
    {"%sgemv", default_types,
        {"integer", "integer", "integer", "integer", "scalar", "scalar_array",
         "integer", "scalar_array", "integer", "scalar", "scalar_array", "integer"}, {}},
    -- BLAS 3
    {"%sgemm", default_types,
        {"integer", "integer", "integer", "integer", "integer", "integer",
         "scalar", "scalar_array", "integer", "scalar_array", "integer",
         "scalar", "scalar_array", "integer"}, {}}
}

for _, func in pairs(blas) do
    local name = string.format(func[1], "")
    S[name] = blas_factory(unpack(func))
end

for k, v in pairs(S) do
    print(k, v)
end

return S
