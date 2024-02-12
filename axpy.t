local C = terralib.includecstring[[
    #include <openblas/cblas.h>
]]
terralib.linklibrary("libcblas.so")

local complex = require("complex")

local complexFloat = complex(float)[1]
local complexDouble = complex(double)[1]

local types = {
    ["s"] = float,
    ["d"] = double,
    ["c"] = complexFloat,
    ["z"] = complexDouble}

local S = {}

local function has_opaque_interface(prefix)
    if prefix == "c" or prefix == "z" then
        return true
    else
        return false
    end
end

local function generate_blas_args(prefix, T, signature)
    local terra_arg = terralib.newlist()
    local statements = terralib.newlist()
    local c_arg = terralib.newlist()

    for _, arg in ipairs(signature) do
        if arg == "integer" then
            local int = symbol(int32)
            terra_arg:insert(int)
            c_arg:insert(int)
        elseif arg == "floating" then
            local floating = symbol(T)
            terra_arg:insert(floating)
            if has_opaque_interface(prefix) then
                local opq = symbol(&opaque)
                c_arg:insert(opq)
                statements:insert(quote
                    var [opq] = [&opaque](&[floating])
                end)
            else
                c_arg:insert(floating)
            end
        elseif arg == "array" then
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
    return terra_arg, statements, c_arg
end

local function blas_factory(name, signature)
    local methods = terralib.newlist()
    for prefix, T in pairs(types) do
        local pname = prefix .. name
        local cname = "cblas_" .. pname
        local terra_arg, statements, c_arg
            = generate_blas_args(prefix, T, signature)

        local func = terra([terra_arg])
            [statements]
            C.[cname]([c_arg])
        end
        methods:insert(func)
    end

    return terralib.overloadedfunction(name, methods)
end

local axpy = blas_factory("axpy", {"integer", "floating", "array",
                                   "integer", "array", "integer"})

S["axpy"] = axpy

return S
