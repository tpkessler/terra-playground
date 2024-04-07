local function tuple_type_to_list(tpl)
    --[=[
        Return list of types in given tuple type

        Args:
            tpl: Tuple type

        Returns:
            One-based terra list composed of the types in the tuple
        
        Examples:
            print(tuple_type_to_list(tuple(int, double))[2])
            -- double
    --]=]

    -- The entries key of a tuple type is a terra list of tables,
    -- where each table stores the index (zero based) and the type.
    -- Hence we can use the map method of a terra list to extract a list
    -- of terra types. For details, see the implementation of the tuples type
    -- https://github.com/terralang/terra/blob/4d32a10ffe632694aa973c1457f1d3fb9372c737/src/terralib.lua#L1762
    return tpl.entries:map(function(t) return t[2] end)
end


local function get_signature_list(func)
    --[=[
        Extract types from function signature

        Args:
            func: Terra function

        Returns:
            Argument and return types in two separate lists.

        Examples:
            print(get_signature_list(terra(x: int, y: float): double end))
            -- {int32,float}	{double}
    --]=]
    assert(terralib.isfunction(func), "Argument must be terra function")
    local input = func.type.parameters

    local ret = func.type.returntype
    local output
    if ret.entries ~= nil then
        output = tuple_type_to_list(ret)
    else
        output = terralib.newlist()
        output:insert(ret)
    end

    return input, output
end

local function cast_signature(T, func, TRef)
    --[=[
        Replace given type and references in function signature with new type

        Args:
            T: new type
            func: Terra function
            TRef: old type, to be replaced

        Returns:
            Argument and return types as separate lists
    --]=]
    local input, output = get_signature_list(func)
    local arg = terralib.newlist()
    local ret = terralib.newlist()

    local cast = function(S)
        if S == TRef then
            return T
        elseif S == &TRef then
            return &T
        else
            return S
        end
    end

    local arg = input:map(cast)
    local ret = output:map(cast)

    return arg, ret
end

local function generate_terra_wrapper(T, c_func, TRef, r_func)
    --[=[
        Generate uniform wrappers for BLAS and LAPACK like functions

        Args:
            T: type for which the wrapper is generated
            c_func: Underlying C function, wrapped as a terra function
            TRef: Reference type for function signature
            r_func: Terra function with model function signature

        Returns:
            Wrapper around c_func for type T with same interface as r_func
    --]=]
    local terra_arg, terra_ret = cast_signature(T, r_func, TRef)
    local terra_sym = terra_arg:map(symbol)
    local sym_ret = terra_ret:map(symbol)

    local c_arg, c_ret = get_signature_list(c_func)

    local statement = terralib.newlist()
    local c_sym = terralib.newlist()
    for i = 1, #terra_arg do
        if terra_arg[i] == T then
            local scalar = symbol(c_arg[i])
            if c_arg[i]:ispointer() then
                statement:insert(quote
                                     var [scalar] = [ c_arg[i] ](&[ terra_sym[i] ])
                                 end)
            else
                statement:insert(quote
                                     var [scalar] = @[ &c_arg[i] ](&[ terra_sym[i] ])
                                 end)
            end
            c_sym:insert(scalar)
        elseif terra_arg[i] == &T then
            local pointer = symbol(c_arg[i])
            statement:insert(quote
                                 var [pointer] = [ c_arg[i] ]([ terra_sym[i] ])
                             end)
            c_sym:insert(pointer)
        else
            c_sym:insert(terra_sym[i])
        end
    end

    -- TODO Return values
    local return_statement = terralib.newlist()
    local c_call
    -- If the number of arguments match, then the return value of the
    -- C call is passed via the return statement.
    -- If the number of arguments of the C call is larger than the number of
    -- arguments of the reference call, we assume that the return value is
    -- passed by reference, so we declare the return value, assign its address
    -- to a pointer of matching c type, call the C function and return
    -- the result by value.
    if #c_arg == #terra_arg then
        c_call = quote return [c_func]([c_sym]) end
    elseif #c_arg == #terra_arg + 1 then
        local ref = symbol(terra_ret[1])
        statement:insert(quote var [ref] end)
        local c_ref = symbol(c_arg[#c_arg])
        statement:insert(quote var [c_ref] = [ c_arg[#c_arg] ](&[ref]) end)
        c_sym:insert(c_ref)
        return_statement:insert(quote return [ref] end)
        c_call = quote [c_func]([c_sym]) end
    else
        error("Unsupported number of return statements")
    end

    local terra wrapper([terra_sym])
        [statement]
        [c_call]
        [return_statement]
    end
    
    return wrapper
end

return {
    generate_terra_wrapper = generate_terra_wrapper
}
