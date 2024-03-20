local C = terralib.includecstring[[
    #include <openblas/cblas.h>
]]

-- Check if pointers to type have to pass as void * pointers to BLAS
local function has_opaque_interface(prefix)
    if prefix == "c" or prefix == "z" then
        return true
    elseif prefix == "sc" or prefix == "dz" then
        return true
    else
        return false
    end
end

-- Generate building blocks for terra wrappers for BLAS/LAPACK
-- prefix: String indicating the type for which terra statements are emitted
-- T: scalar type. Can a be a real or complex floating point type
-- signature: Abstraction of the actual BLAS call. A list of strings.
-- 			  Supported types are:
--			  					  * integer for lengths, increments or enums
--								  * scalar for the scaling of arrays
--								  * scalar_array for pointers to arrays of type scalar
--			  An example signature for ?axpy is
--			  		{"integer", "scalar", "scalar_array", "integer", "scalar_array", "integer"}
-- return_val: Abstraction of return values of the BLAS call. A list of strings.
--			   Supported types are:
--			   					   * real_scalar for the return values of norms or similar
--								   * scalar for general scalar-valued functions
--								   * integer for indices
-- Returns
-- terra_arg: A list of symbols for the terra function call
-- statements: Optional casts from terra types to BLAS arguments
-- c_arg: A list of symbols for the C function call
-- result: If nil then the BLAS function has no return value.
--         Otherwise it contains a symbol and must be assigned the return of the C call.
-- return_statement: List of terra symbols that close the terra function call
local function parser(prefix, T, signature, return_val)
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
            local Ts = T.scalar_type or T
            result = symbol(Ts)
            return_statement:insert(quote
                return [result]
            end)
        elseif arg == "scalar" then
            if has_opaque_interface(prefix) then
                local call_by_ref = symbol(&opaque)
                local result_cast = symbol(T)
                statements:insert(quote
                    var [result_cast]
                    var [call_by_ref] = &[result_cast]
                end)
                c_arg:insert(call_by_ref)
                return_statement:insert(quote
                    return [result_cast]
                end)
            else
                result = symbol(T)
                return_statement:insert(quote
                    return [result]
                end)
            end
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

-- Generate an overloaded terra function for a given BLAS function
-- name: Format string to include the name of the BLAS function with prefix and optional suffix.
-- types: table that maps prefixes to terra types.
-- suffix_types: table that maps the type prefix to optional suffixes.
-- signature: Table of strings for the arguments of the BLAS call as described in parser().
-- return_val: Table of strings for the return values of the BLAS call as described in parser().
local function factory(name, types, suffix_types, signature, return_val)
    local methods = terralib.newlist()
    for prefix, T in pairs(types) do
        local tname = string.format(name, "", "")
        local suffix = suffix_types[prefix] or ""
        local pname = string.format(name, prefix, suffix)
        local cname = "cblas_" .. pname
        local terra_arg, statements, c_arg, result, return_statement
            = parser(prefix, T, signature, return_val)

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

return {factory = factory}
