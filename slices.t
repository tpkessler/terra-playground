-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local base = require("base")
local sarray = require("sarray")
local range = require("range")

local size_t = uint64

local SMatrix = sarray.StaticMatrix(int, {3, 7}, {perm={1,2}} )

local function Slice(a, stride, b)

    local struct slice{
    }

    function slice.metamethods.__typename(self)
        return ("Slice(%d:%d:%d)"):format(tostring(a), tostring(stride), tostring(b))
    end

    slice.a = a
    slice.b = b
    slice.stride = stride
    slice.isslice = true

    function slice:length()
        return math.ceil((slice.b - slice.a) / slice.stride)
    end

    slice.metamethods.__entrymissing = macro(function(entryname, self)
        if entryname == "a" then
            return `a
        elseif entryname == "b" then
            return `b
        elseif entryname == "stride" then
            return `stride
        end
    end)

    slice.metamethods.__apply = macro(function(self, i)
        return `a + stride * i
    end)

    return slice
end

local struct colon{
}
colon.isslice = true

local slice = macro(function(args)
    local args = terralib.newlist(args:asvalue())
    if #args == 3 then
       return Slice(unpack(args))
    end
end)

local SlicedSMatrix = function(ParentMatrix, ...)

    assert(ParentMatrix.ndims == 2)
    local Ranges = terralib.newlist{...}
    assert(#Ranges == 2)
    if Ranges[1].b == -1 then Ranges[1].b = ParentMatrix.size[1] end
    if Ranges[2].b == -1 then Ranges[2].b = ParentMatrix.size[2] end
    
    local T = ParentMatrix.eltype
    local Size = Ranges:map(function(v) return v:length() end)
    local Perm = ParentMatrix.perm

    local __ranges = { terralib.constant(terralib.new(Ranges[1], {})), terralib.constant(terralib.new(Ranges[2], {})) }

    local SMatrix = sarray.SArrayRawType(T, Size, {perm=Perm, cumulative_size=ParentMatrix.cumsize} )

    function SMatrix.metamethods.__typename(self)
        return ("View{SMatrix(%s, {%d, %d})}"):format(tostring(T), ParentMatrix.size[1], ParentMatrix.size[2])
    end

    --add base functionality
    base.AbstractBase(SMatrix)

    SMatrix.methods.slice = macro(function(self, k, ...)
        local indices = terralib.newlist{...}
        local K = k:asvalue()+1
        local index = indices[ SMatrix.perm[K] ]
        local range = __ranges[K]
        return `range([index])
    end)

    --implement interfaces
    sarray.SArrayStackBase(SMatrix)
    sarray.SArrayVectorBase(SMatrix)
    sarray.SArrayIteratorBase(SMatrix)

    return SMatrix
end


local ffi = require("ffi")

local function slice(arg)
    local function getvalue(e)
        if type(e.value) == "userdata" then
            return tonumber(ffi.cast("uint64_t *",e.value)[0])
        else
            if e.operator == "-" then
                return -getvalue(e.operands[1])
            end
        end
    end
    if arg:gettype().convertible == "tuple" then
        local expr = arg.tree.expressions
        if #expr == 2 then
            --default stride == 1
            return Slice(getvalue(expr[1]), 1, getvalue(expr[2]))
        elseif #expr == 3 then
            --custom stride
            return Slice(getvalue(expr[1]), getvalue(expr[2]), getvalue(expr[3]))
        end
    else
        local value = arg:asvalue()
        if type(value) == "table" and value.name == "colon" then
            return Slice(0, 1, -1)
        elseif type(value) == "number" then
            return Slice(value, 1, value + 1)
        end
    end
end


SMatrix.metamethods.__apply = macro(function(self, ...)
    local indices = terralib.newlist{...}
    if #indices == 1 then
        if indices[1].tree.type.convertible == "tuple" then
            return `self:data( self:getlinearindex(unpacktuple([indices])) )
        else
            local index = indices[1] 
            return `self:data( [index] )
        end
    elseif #indices == 2 then
        local I, J = slice(indices[1]), slice(indices[2])

        if I and J then
            local MatrixView = SlicedSMatrix(SMatrix, I, J)
            return `[&MatrixView](&self)
        else
            return `self:data( self:getlinearindex([ indices[1] ], [ indices[2] ]) )
        end
    end
end)


terra main()

    var A = SMatrix.from({
        {1,  2,   3,  4,  5,  6,  7},
        {8,  9,  10, 11, 12, 13, 14},
        {14, 16, 17, 18, 19, 20, 21}
    })
    A:print()

    var B = A(2, {1,2,-1})
    B:print()

end
main()