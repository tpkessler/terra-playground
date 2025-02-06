-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local base = require("base")
local concepts = require("concepts")
local err = require("assert")
local range = require("range")
local tpl = require("tuple")

local DYNAMIC_EXTEND = setmetatable(
    {}, {__tostring = function(self) return "DynamicExtend" end}
)
local Span = terralib.memoize(function(T, N)
    N = N or DYNAMIC_EXTEND

    local struct span {
        ptr: &T
        len: int64
    }

    function span.metamethods.__typename(self)
        return ("Span(%s, %s)"):format(tostring(T), tostring(N))
    end

    base.AbstractBase(span)
    span.traits.eltype = T
    span.traits.length = (N == DYNAMIC_EXTEND) and concepts.traittag or N

    local getlen = macro(function(sp)
        return (N == DYNAMIC_EXTEND) and quote in sp.len end or N
    end)

    span.metamethods.__apply = macro(function(self, idx)
        return quote err.assert(idx < getlen(self)) in self.ptr[idx] end
    end)

    span.metamethods.__cast = function(from, to, exp)
        if from:isarray() then
            assert(from.type == T)
            local len = from.N
            if N ~= DYNAMIC_EXTEND then
                assert(len == N)
            end
            return `span {&[exp][0], from.N}
        elseif from:ispointer() then
            assert(from.type == T)
            return `span {exp, 1}
        elseif tpl.istuple(from) then
            local types = tpl.unpacktuple(from)
            local len = #from.entries
            if len == 2 and types[1] == &T then
                return `span {exp._0, exp._1}
            else
                if N ~= DYNAMIC_EXTEND then
                    assert(len == N)
                end
                local arg = terralib.newlist()
                for i = 1, len do
                    arg:insert(`[exp].["_" .. (i - 1)])
                end
                return quote
                        var a = arrayof(T, [arg])
                    in
                        span {&a[0], len}
                    end
            end
        else
            error("Cannot convert to span")
        end
    end

    terra span:data()
        return self.ptr
    end

    terra span:size()
        return getlen(self)
    end

    terra span:front()
        return self.ptr[0]
    end

    terra span:back()
        return self.ptr[self.len - 1]
    end

    terra span:first(n: int64)
        err.assert(n < self:size())
        return span {self.ptr, n}
    end

    terra span:last(n: int64)
        var sz = self:size()
        err.assert(n > 0 and n <= sz)
        return span {self.ptr + sz - n, n}
    end

    terra span:subspan(offset: int64, count: int64)
        var sz = self:size()
        err.assert(offset + count <= sz)
        return span {self.ptr + offset, count}
    end

    local struct iterator {
        parent: &span
        ptr: &T
    }

    terra span:getiterator()
        return iterator {self, self.ptr}
    end

    terra iterator:isvalid()
        return (self.ptr - self.parent.ptr) < getlen(self.parent)
    end

    terra iterator:next()
        self.ptr = self.ptr + 1
    end

    terra iterator:getvalue()
        return @self.ptr
    end

    range.Base(span, iterator)
    return span
end)

return {
    Span = Span,
}
