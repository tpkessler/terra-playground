local C = terralib.includecstring[[
    #include <openblas/cblas.h>
]]
terralib.linklibrary("libcblas.so")

local types = {["s"] = float, ["d"] = double}

local S = {}

local name = "axpy"
local methods = {}
for prefix, T in pairs(types) do
    local pname = prefix..name
    local cname = string.format("cblas_%s", pname)
    local signature = {symbol(int32), symbol(T), symbol(&T), symbol(int32), symbol(&T), symbol(int32)}
    local func = terra([signature])
        C.[cname]([signature])
    end
    S[pname] = func
    methods[#methods + 1] = func
end
S[name] = terralib.overloadedfunction("axpy", methods)

return S
