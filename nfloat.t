-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

require "terralibext"

local uname = io.popen("uname", "r"):read("*a")

-- Wrap FLINT without inlines
local flint = terralib.includec("flint/nfloat.h", {"-DNFLOAT_INLINES_C=1"})
local gr = terralib.includec("flint/gr.h", {"-DGR_INLINES_C=1"})
if uname == "Darwin\n" then
    terralib.linklibrary("libflint.dylib")
elseif uname == "Linux\n" then
    terralib.linklibrary("libflint.so")
else
    error("Not implemented for this OS.")
end

local base = require("base")
local mathfun = require("mathfuns")
local concept = require("concept")

local suffix = {64, 128, 192, 256, 384, 512, 1024, 2048, 4096}
local float_type = {}
local context = {}
for _, N in pairs(suffix) do
    float_type[N] = flint[string.format("nfloat%d_struct", N)]
    -- Meta information on fixed precision floats is stored in a context.
    -- Mathematically, they represent rings.
    -- Here, we store them as global variables in a table such that
    -- each float type has exactly one context it will use.
    context[N] = global(flint.gr_ctx_t)
    local ctx = context[N]:get()
    -- Call clean_context() to release memory allocated by nfloat_ctx_init
    flint.nfloat_ctx_init(ctx, N, 0)
end

local unary_math = {
    "abs",
    "sqrt",
    "floor",
    "ceil",
    "exp",
    "expm1",
    "log",
    "log1p",
    "sin",
    "cos",
    "tan",
    "sinh",
    "cosh",
    "tanh",
    "gamma",
}

local binary_math = {
    "pow",
}

concept.NFloat = terralib.types.newstruct("NFloat")
concept.Base(concept.NFloat)
concept.NFloat.traits.precision = concept.traittag

--extract the exponent of an nfloat
local exponent = macro(function(value)
    return quote
        var tmp = [&uint32](&value.data.head)
    in
        @tmp
    end
end)

--extract the sign of an nfloat
local sign = macro(function(value)
    return quote
        var sign = [&uint32](&value.data.head[1])
        var s = 1
        if @sign % 2 == 1 then s = -1 end
    in
        s
    end
end)

--extract the significant 64-bit part of the mantissa of an nfloat
local significant_part_mantissa = macro(function(value)
    local M = value:gettype().type.traits.precision / 64
    return quote
        var n = [&uint64](&value.data.d[M-1])
    in
        @n
    end
end)

--shift significat 64-bit part of mantissa
local terra shiftandscale(n : uint64, e : int)
    var res = n
    var k = 0
    while n > 0 do
        k = k + 1
        n = n << 1
    end
    return mathfun.ldexp(double(res >> 64 - k), e-k)
end


local FixedFloat = terralib.memoize(function(N)
    local ctype = float_type[N]
    assert(ctype, "No support for precision " .. N .. " in FixedFloat")
    local ctx = context[N]:get()

    local struct nfloat {
        data: ctype
    }

    function nfloat.metamethods.__typename()
        return string.format("FixedFloat(%d)", N)
    end

    base.AbstractBase(nfloat)

    --type traits
    nfloat.traits.precision = N

    local terra new()
        var data: ctype
        flint.nfloat_init(&data, ctx)
        return nfloat {data}
    end

    local terra from_double(x: double)
        var f = new()
        flint.nfloat_set_d(&f.data, x, ctx)
        return f
    end
    local terra from_str(s: rawstring)
        var f = new()
        flint.nfloat_set_str(&f.data, s, ctx)
        return f
    end
    local from = terralib.overloadedfunction("from", {from_double, from_str})

    local to_str = macro(function(x)
        local digits = math.floor(N * (math.log(2) / math.log(10)))
        return quote
                var str: rawstring
                -- TODO: Fix memory leak
                -- defer flint.flint_free(str)
                gr.gr_get_str_n(&str, &x.data, [digits], ctx)
            in
                str
        end        
    end)

    function nfloat.metamethods.__cast(from, to, exp)
        if to == nfloat then
            if from:isarithmetic() then
                return `from_double(exp)
            elseif from:ispointer() and from.type == int8 then
                return `from_str(exp)
            else
                error("Cannot cast from " .. from .. " to " .. to)
            end
        end
        error("Unknown type")
    end

    local binary = {
        __add = flint.nfloat_add,
        __mul = flint.nfloat_mul,
        __sub = flint.nfloat_sub,
        __div = flint.nfloat_div,
    }
    for key, method in pairs(binary) do
        nfloat.metamethods[key] = terra(self: nfloat, other:nfloat)
            var res = new()
            [method](&res.data, &self.data, &other.data, ctx)
            return res
        end
    end

    local terra fmod(value : nfloat, modulus : nfloat)
        var tmp = new()
        flint.nfloat_div(&tmp.data, &value.data, &modulus.data, ctx)
        flint.nfloat_floor(&tmp, &tmp, ctx)
        flint.nfloat_mul(&tmp.data, &tmp.data, &modulus.data, ctx)
        flint.nfloat_sub(&tmp.data, &value.data, &tmp.data, ctx)
        return tmp
    end
    mathfun["fmod"]:adddefinition(fmod)

    nfloat.metamethods.__mod = terra(self: nfloat, other: nfloat)
        return fmod(self, other)
    end

    local unary = {
        __unm = flint.nfloat_neg,
    }
    for key, method in pairs(unary) do
        nfloat.metamethods[key] = terra(self: nfloat)
            var res = new()
            [method](&res.data, &self.data, ctx)
            return res
        end
    end

    local function cmp(sign)
        local terra impl(self: &ctype, other: &ctype, ctx: flint.gr_ctx_t)
            var res = 0
            flint.nfloat_cmp(&res, self, other, ctx)
            return res == sign
        end

        return impl
    end

    local boolean = {
        __eq = cmp(0),
        __lt = cmp(-1),
        __gt = cmp(1),
    }

    for key, method in pairs(boolean) do
        nfloat.metamethods[key] = terra(self: nfloat, other: nfloat)
            return [method](&self.data, &other.data, ctx)
        end
    end

    nfloat.metamethods.__le = terra(self: nfloat, other: nfloat)
        return self < other or self == other
    end

    nfloat.metamethods.__ge = terra(self: nfloat, other: nfloat)
        return self > other or self == other
    end

    local terra round(value : nfloat)
        value = value + 0.5
        flint.nfloat_floor(&value, &value, ctx)
        return value
    end
    mathfun["round"]:adddefinition(round)

    local terra pi()
        var res = new()
        flint.nfloat_pi(&res, ctx)
        return res
    end

    terra nfloat:truncatetodouble()
        var m = significant_part_mantissa(self)
        var e = exponent(self)
        var s = sign(self)
        return s * shiftandscale(m, e)
    end

    for _, func in pairs(unary_math) do
        local name = "nfloat_" .. func
        local terra impl(x: nfloat)
            var y: nfloat
            flint.[name](&y.data, &x.data, ctx)
            return y
        end
        mathfun[func]:adddefinition(impl)
    end

    for _, func in pairs(binary_math) do
        local name = "nfloat_" .. func
        local terra impl(x: nfloat, y: nfloat)
            var z: nfloat
            flint.[name](&z.data, &x.data, &y.data, ctx)
            return z
        end
        mathfun[func]:adddefinition(impl)
    end

    mathfun.min:adddefinition(terra(x : nfloat, y : nfloat)
                                  return terralib.select(x < y, x, y)
                              end)
    mathfun.max:adddefinition(terra(x : nfloat, y : nfloat)
                                  return terralib.select(x > y, x, y)
                              end)
    mathfun.conj:adddefinition(terra(x: nfloat) return x end)
    mathfun.real:adddefinition(terra(x: nfloat) return x end)
    mathfun.imag:adddefinition(terra(x: nfloat) return [nfloat](0) end)

    do
        local terra impl(x: nfloat, y: nfloat, z: nfloat)
            return x * y + z
        end
        mathfun.fusedmuladd:adddefinition(impl)
    end

    for k, v in pairs({from = from, tostr = to_str, pi = pi}) do
        nfloat.staticmethods[k] = v
    end

    for _, C in pairs({"NFloat", "Real", "Float", "Number"}) do
        concept[C].friends[nfloat] = true
    end

    return nfloat
end)

local terra clean_context()
    escape
        for _, N in pairs(suffix) do
            local val = context[N]:get()
            emit quote
                gr.gr_ctx_clear(val)
            end
        end
    end
end

return {
    FixedFloat = FixedFloat,
    clean_context = clean_context
}
