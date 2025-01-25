-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local io = terralib.includec("stdio.h")
local err = require("assert")
local tup = require("tuple")
local tmath = require("tmath")
local range = require("range")
local luafun = require("fun")

local size_t = uint64

local linrange = {}
linrange.__index = linrange
linrange.__metatable = linrange

function linrange.new(n)
    local t = {}
    t.n = n
    return setmetatable(t, linrange)
end

function linrange:next(i)
    local i = i+1
    if i < self.n then
        return i
    end
end

function linrange:iterate()
    return linrange.next, self, -1
end

local function next(sizes, iter, i, k)
    i[k] = iter[k]:next(i[k])
    if i[k] then
        return true
    else
        if k>1 then
            iter[k] = linrange.new(sizes[k])
            i[k] = iter[k]:next(-1)
            return next(sizes, iter, i, k-1)
        end
    end
    return false
end

local productiter = function(...)
    local sizes = terralib.newlist{...}
    local m = #sizes
    local iter = sizes:map(function(s) return linrange.new(s) end)
    local i = sizes:map(function(s) return 0 end)
    i[m] = -1
    return function()
        if next(sizes, iter, i, m) then
            return i
        end
    end
end

local getarrayentryfromexpressiontree = function(args, multiindex)
    local data = args
    for k = 1, #multiindex do
        data = data.expressions[multiindex[k]+1]
    end
    return data
end

local function defaultperm(dimension)
    return terralib.newlist(
        luafun.totable(
            luafun.range(dimension, 1, -1)
        )
    )
end

local function checkperm(perm)
    assert(terralib.israwlist(perm), "ArgumentError: input should be a raw list.")
    local linrange = perm:mapi(function(i,v) return i end)
    for i,v in ipairs(perm) do
        linrange[v] = nil
    end
    assert(#linrange == 0, "ArgumentError: input list is not a valid permutation.")
end

local function isstatic(Array)
    return Array.traits.size ~= nil
end

local function isdynamic(Array)
    return Array.traits.size == nil
end


--ArrayBase collects some common utilities used to built 
--static and dynamic Array types. The following traits
--and methods are assumed
--  Array.traits.eltype
--  Array.traits.ndims
--  Array.traits.perm
--  Array.methods.length
--  Array.methods.size
--  Array.methods.cumsize
--  self:data
local ArrayBase = function(Array)

    local T = Array.traits.eltype
    local N = Array.traits.ndims

    local Unitrange = range.Unitrange(size_t)

    --local terra array holding the permutation array
    local __perm = terralib.constant(terralib.new(size_t[N], Array.traits.perm))
    local rowmajorperm = defaultperm(N) --the standard permutation
    
    --given multi-indices {i_1, i_2, ..., i_D}
    --compute the linear index as follows (assuming perm={D, D-1, ... , 1}):
    --l = i_d + 
    --    Size[D] * i_{d-1} + 
    --    Size[D] * Size[D-1] * i_{d-2} +
    --    .
    --    .
    --    Size[D] * Size[D-1] * ... * Size[2] * i_{1}
    local Indices = rowmajorperm:map(function(v) return symbol(size_t) end)

    --cumulative sizes as a terra method
    if not Array.methods.cumsize then
        if isstatic(Array) then
            --static array
            Array.methods.cumsize = macro(function(self, i)
                return `[ Array.traits.cumsize[i:asvalue()+1] ]
            end)
        else
            --dynamic array
            Array.methods.cumsize = macro(function(self, i)
                return `self.cumsize[i]
            end)
        end
    end

    --default slice method
    --just returns the linear index
    if not Array.methods.slice then
        Array.methods.slice = macro(function(self, k, ...)
            local indices = terralib.newlist{...}
            local i = Array.traits.perm[k:asvalue()+1]
            return `[ indices[i] ]
        end)
    end

    local terra boundscheck_linear(self : &Array, index : size_t)
        err.assert(index < self:length(), "BoundsError: out of bounds.")
    end

    local terra boundscheck_cartesian(self : &Array, [Indices])
        escape
            for d = 1, N do
                local index = Indices[d]
                local message = "BoundsError: array dimension " .. tostring(d) .. " out of bounds."
                emit quote
                    err.assert([index] < self:size([d-1]), message)
                end
            end
        end
    end

    Array.methods.boundscheck = macro(function(self, ...)
        if __boundscheck__ then
            local indices = terralib.newlist{...}
            if #indices == 1 then
                return `boundscheck_linear(&self, [indices])
            else
                return `boundscheck_cartesian(&self, [indices])
            end
        end
    end)

    if N == 1 then
        terra Array:getlinearindex(index : size_t) : size_t
            self:boundscheck(index)
            return index
        end
    else
        terra Array:getlinearindex([Indices]) : size_t
            self:boundscheck(Indices)
            var lindex = self:slice(0, [Indices])
            escape
                for k = 1, N-1 do
                    emit quote
                        lindex = lindex + self:cumsize([k-1]) * self:slice([k], [Indices])
                    end
                end
            end
            return lindex
        end
    end
    Array.methods.getlinearindex:setinlined(true)

    local get = terra(self : &Array, index : size_t)
        self:boundscheck(index)
        return self:getdata(index)
    end
    
    local set = terra(self : &Array, index : size_t, x : T)
        self:boundscheck(index)
        self:setdata(index, x)
    end
    
    if N == 1 then
        Array.methods.get = get
        Array.methods.set = set
    else
        Array.methods.get = terralib.overloadedfunction("get", 
        {
            get,
            terra(self : &Array, [Indices])
                return self:getdata(self:getlinearindex([Indices]))
            end
        })
        
        Array.methods.set = terralib.overloadedfunction("set",
        {
            set, 
            terra(self : &Array, [Indices], x : T)
                self:setdata(self:getlinearindex([Indices]), x)
            end
        })
    end

    if not Array.metamethods.__apply then
        Array.metamethods.__apply = macro(function(self, ...)
            local indices = terralib.newlist{...}
            assert(#indices == 1 or #indices == N, "ArgumentError: invalid argument dimensions.")
            if #indices==1 then
                return `self:getdata([ indices[1] ])
            else
                return `self:getdata(self:getlinearindex([indices]))
            end
        end)
    end

    --[[
    if not Array.metamethods.__update then
        Array.metamethods.__update = macro(function(self, ...)
            local args = terralib.newlist{...}
            return `self:set([args])
        end)
    end
    --]]

    local function fillarray(A, arraysize, args)
        return quote
            escape
                for mi in productiter(unpack(arraysize)) do
                    local value = getarrayentryfromexpressiontree(args, mi)
                    emit quote 
                        [A]:set([ mi ], [ value ])
                    end
                end
            end
        end
    end

    local function getarraysize(args)
        local arraysize = terralib.newlist()
        while args.expressions do
            assert(terralib.israwlist(args.expressions))
            arraysize:insert(#args.expressions)
            args = args.expressions[1]
        end
        return arraysize
    end

    if isstatic(Array) then
        --case of a static array we check if the sizes are consistent with the input
        local checkarraysize = function(arraysize)
            for k = 1, N do
                assert(arraysize[k] == Array.traits.size[k], "ArgumentError: sizes in dimension " .. tostring(k) .. " is not consistent with array dimensions.")
            end
        end
        --case static array, no allocator
        Array.staticmethods.from = macro(function(args)
            local data = args.tree
            local arraysize = getarraysize(data)
            checkarraysize(arraysize)
            return quote
                var A : Array
                [fillarray(A, arraysize, data)]
            in
                A
            end
        end)
    else
        --case of a dynamic array there is an allocator
        Array.staticmethods.from = macro(function(alloc, args)
            local data = args.tree
            local arraysize = getarraysize(data)
            return quote
                var A = Array.new([alloc], {[arraysize]})
                [fillarray(A, arraysize, data)]
            in
               __move__(A)
            end
        end)
    end

    --return linear indices product range
    local function getunitranges(K)
        return terra(self : &Array)
            var uranges : tup.ntuple(Unitrange, K)
            escape
                for k = 1, K do
                    local s = "_" .. tostring(k-1)
                    emit quote uranges.[s] = Unitrange{0, self:size([k-1])} end
                end
            end
            return uranges
        end
    end

    --return linear indices product range
    if not Array.methods.indexrange then
        Array.methods.indexrange = macro(function(self, i)
            return `Unitrange{0, self:size([i:asvalue()])}
        end)
    end

    local printarray
    if N == 1 then
        printarray = function(self, name)
            return quote
                escape
                    if name then
                        emit quote io.printf("%s = \n", [ name ]) end
                    end
                end
                for i in self:indexrange(0) do
                    var value = self:get(i)
                    io.printf("[%s]\n", tmath.numtostr(value))
                end
                io.printf("\n")
            end
        end
    elseif N == 2 then
        printarray = function(self, name)
            return quote
                escape
                    if name then
                        emit quote io.printf("%s = \n", [ name ]) end
                    end
                end
                for i in self:indexrange(0) do
                    io.printf("\t[")
                    for j in self:indexrange(1) do
                        var value = self:get(i, j)
                        io.printf("%s\t", tmath.numtostr(value))
                    end
                    io.printf("]\n")
                end
                io.printf("\n")
            end
        end
    else
        printarray = function(self, name)
            local unitranges = getunitranges(N-2) --terra function that returns the first N-2 unitranges
            local p = rowmajorperm:filteri(function(i,v) return i <= N - 2 end)
            local ntimes = p:mapi(function(i,v) return "%d" end)
            local slice = name .."[" .. table.concat(ntimes,",") .. ", :, :] = \n"
            return quote
                var K = unitranges(&self)
                for k in range.product(unpacktuple(K)) do
                    io.printf([ slice ], unpacktuple(k))
                    for i in self:indexrange(N-2) do
                        io.printf("\t[")
                        for j in self:indexrange(N-1) do
                            var value = self:get(unpacktuple(k), i, j)
                            io.printf("%s\t", tmath.numtostr(value))
                        end
                        io.printf("]\n")
                    end
                    io.printf("\n")
                end
            end
        end
    end

    Array.methods.print = macro(function(self)
        if self.tree.name then
            --case when self is a value
            return printarray(self, self.tree.name)
        elseif self.tree.operands then
            --case when self is dereferenced
            return printarray(self, self.tree.operands[1].name)
        end
    end)

    --element size as a terra method
    Array.methods.perm = terralib.overloadedfunction("perm", {
        terra(self : &Array, i : size_t)
            return __perm[i]
        end,
        terra(self : &Array)
            return __perm
        end
    })

    return {
        getunitranges = getunitranges
    }
end


return {
    productiter = productiter,
    checkperm = checkperm,
    defaultperm = defaultperm,
    ArrayBase = ArrayBase
}