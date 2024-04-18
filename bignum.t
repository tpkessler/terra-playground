-- Wrap FLINT without inlines
local flint = terralib.includec("flint/fmpz.h", {"-DFMPZ_INLINES_C=1"})
terralib.linklibrary("libflint.so")
local io = terralib.includec("stdio.h")
local alloc = require("alloc")

local function BigInt()

    -- The fault type of flint is fmpz_t, an array of length one and of type
    -- fmpz.
    local struct bigint {
        data: flint.fmpz
    }

    -- fmpz is a int64 by default. If the number is too big
    -- to be represented by int64, the value now points to allocated memory.
    -- Hence, depending on the contet, we have to free memory when a bigint
    -- goes out of scope.
    local new = macro(function()
        return quote
                var x = bigint {}
                flint.fmpz_init(&x.data)
                defer x:free()
            in
                x
        end
    end)

    terra bigint:free()
        flint.fmpz_clear(&self.data)
    end

    local terra from_int(x: int64)
        var xb = new()
        flint.fmpz_set_si(&xb.data, x)
        return xb
    end

    local terra from_str(s: &int8)
        var xb = new()
        flint.fmpz_set_str(&xb.data, s, 10)
        return xb
    end

    local to_str = macro(function(x, b)
        b = b or 10
        return quote
                var size = flint.fmpz_sizeinbase(&x.data, b)
                var A: alloc.Default
                var str: &int8 = [&int8](A:alloc(size + 1))
                defer A:free(str)
                flint.fmpz_get_str(str, b, &x.data)
            in
                str
        end
    end)

    function bigint.metamethods.__cast(from, to, exp)
        if to == bigint then
            if from:isarithmetic() then
                return `from_int(exp)
            elseif from:ispointer() and from.type == int8 then
                return `from_str(exp)
            end
        end
        error("Unknown type")
    end

    function bigint.metamethods.__typename()
        return "BigInt"
    end

    terra bigint.metamethods.__add(self: bigint, other: bigint)
        var res = new()
        flint.fmpz_add(&res.data, &self.data, &other.data)
        return res
    end

    terra bigint.metamethods.__mul(self: bigint, other: bigint)
        var res = new()
        flint.fmpz_mul(&res.data, &self.data, &other.data)
        return res
    end

    terra bigint.metamethods.__unm(self: bigint)
        var res = new()
        flint.fmpz_neg(&res.data, &self.data)
        return res
    end

    terra bigint.metamethods.__sub(self: bigint, other: bigint)
        var res = new()
        flint.fmpz_sub(&res.data, &self.data, &other.data)
        return res
    end

    terra bigint.metamethods.__div(self: bigint, other: bigint)
        var res = new()
        flint.fmpz_tdiv_q(&res.data, &self.data, &other.data)
        return res
    end

    terra bigint.metamethods.__eq(self: bigint, other: bigint)
        return flint.fmpz_equal(&self.data, &other.data)
    end

    local static_methods = {
        from = terralib.overloadedfunction("from", {from_int, from_str}),
        to_str = to_str,
    }

    bigint.metamethods.__getmethod = function(self, methodname)
        local self_method = bigint.methods[methodname]
        if self_method then
            return self_method
        end

        local static_method = static_methods[methodname]
        if static_method then
            return static_method
        end

        error("No method " .. methodname .. "defined on " .. self)
    end

    return bigint
end

local BigInt = BigInt()
local io = terralib.includec("stdio.h")
terra main()
    var xb = BigInt.from(10)
    var yb: BigInt = 10
    var a: BigInt = "359235892394"
    for k = 0, 12 do
        a = a * a
    end
    var zb = BigInt.from("10")
    var ab = xb * yb
    io.printf("z = %s\n", zb:to_str())
    io.printf("%d\n", xb == yb)
    io.printf("%d\n", xb == zb)
    io.printf("a = %s\n", a:to_str())
end

main()
