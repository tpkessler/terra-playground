-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local vec = require("luavector")
local tmath = require("mathfuns")

local size_t = uint64
local T = double

--return a terra tuple type of length N: {T, T, ..., T}
local ntuple = function(T, N)
    local t = terralib.newlist()
    for i = 1, N do
        t:insert(T)
    end
    return tuple(unpack(t))
end

function table.copy(t)
    local u = { }
    for k, v in pairs(t) do u[k] = v end
    return setmetatable(u, getmetatable(t))
end

local Interval = {}
Interval.__index = Interval
Interval.__metatable = Interval

function Interval.isa(t)
    return getmetatable(t) == Interval
end

Interval.new = function(a, b)

    assert(type(a)=="number" and type(b)=="number" and "a and b need to be real numbers.")
    assert(a < b)

    --new table
    local interval = {}

    --accessible values
    interval.eltype = T
    interval.a = a
    interval.b = b

    --metatable
    return setmetatable(interval, Interval)
end

function Interval:isinside(x) return (self.a <= x) and (x <= self.b) end

function Interval:__tostring()
    return "interval("..tostring(self.a)..", " ..tostring(self.b)..")"
end

function Interval:__eq(other)
    return self.a==other.a and self.b==other.b
end

function Interval:__call(x)
    return self.a * (1 - x) + self.b * x
end

function Interval:__add(x)
    if type(x)=="number" then
        return Interval.new(self.a + x, self.b + x)
    elseif type(self)=="number" then
        return Interval.new(x.a + self, x.b + self)
    else
        error("Wrong input arguments.")
    end
end

function Interval:__sub(other)
    if type(other)=="number" then
        return Interval.new(self.a - other, self.b - other)
    elseif type(self)=="number" then
        return Interval.new(-other.b + self, -other.a + self)
    else
        error("Wrong input arguments.")
    end
end

function Interval:__unm()
    return Interval.new(-self.b, -self.a)
end

function Interval:barycentriccoord(y)
    return (y - self.a) / (self.b - self.a)
end

function Interval:vol()
    return math.abs(self.b-self.a)
end

function Interval.intersection(self, other)
    
    --check input arguments
    for i,v in ipairs({self, other}) do
        if not (type(v)=="number" or type(v)=="table" and Interval.isa(v)) then
            error("Ecpected numbers and/or intervals as input.")
        end
    end

    local intersection_point_point = function(point_a, point_b)
        if point_a==point_b then
            return point_a
        else
            return nil
        end
    end

    local intersection_interval_point = function(interval, point)
        if interval:isinside(point) then
            return point
        else
            return nil
        end
    end

    local intersection_interval_interval = function(self, other)
        if self == other then
            return self
        else
            local a, b = math.max(self.a, other.a), math.min(self.b, other.b)
            if a < b then
                --intersection is a non-empty interval
                return Interval.new(a, b)
            elseif a==b then
                --intersection is a point
                return a
            else
                --no common intersection
                return nil 
            end
        end
    end

    local get_intersection_type = function(a, b)
        if type(a)=="number" and type(b)=="number" then
            return intersection_point_point(a, b)
        elseif type(a)=="number" and type(b)=="table" and Interval.isa(b) then
            return intersection_interval_point(b, a)
        elseif type(b)=="number" and type(a)=="table" and Interval.isa(a) then
            return intersection_interval_point(a, b)
        elseif type(a)=="table" and type(b)=="table" and Interval.isa(a) and Interval.isa(b) then
            return intersection_interval_interval(a, b)
        else
            error("Function arguments need to be a primitives or intervals.")
        end
    end

    return get_intersection_type(self, other)
end


Hypercube = {}
Hypercube.__index = Hypercube
Hypercube.__metatable = Hypercube

function Hypercube.isa(t)
    return getmetatable(t) == Hypercube
end

Hypercube.new = function(...)

    local args = terralib.newlist{...}
    local N = #args

    --generate inverse permutation
    local invperm = terralib.newlist()
    local volume = 1
    local origin = terralib.newlist()
    local D = 0
    local alpha, beta = 1, N
    for i, v in ipairs(args) do
        if type(v)=="number" then
            invperm[i] = beta
            beta = beta - 1
            origin:insert(v)
        elseif Interval.isa(v) then
            invperm[i] = alpha
            D = D + 1
            volume = volume * v:vol()
            alpha = alpha + 1
            origin:insert(v.a)
        else
            error("Arguments should be an interval or a number.")
        end
    end
    --generate permutation
    local perm = terralib.newlist()
    for i = 1, N do
        perm[ invperm[i] ] = i
    end

    --new table
    local hypercube = {}

    --static data member
    hypercube.I = args
    hypercube.perm = perm
    hypercube.invperm = invperm
    hypercube.origin = origin

    local typename = terralib.newlist()
    for k = 1, N do
        typename:insert(tostring(hypercube.I[k]))
    end
    hypercube.typename = "hypercube(" .. table.concat(typename,",") ..")" 

    function hypercube:vol()
        return volume
    end

    function hypercube:dim()
        return D
    end

    function hypercube:rangedim()
        return N
    end

    function hypercube:issingulardir(i)
        return invperm[i] > D
    end

    return setmetatable(hypercube, Hypercube)
end

function Hypercube:__tostring()
    return self.typename
end

function Hypercube:__eq(other)
    if self:rangedim()==other:rangedim() then
        for i=1, self:rangedim() do 
            if self.I[i] ~= other.I[i] then
                return false
            end
        end
        return true
    end
    return false
end

function Hypercube:__call(x)
    if (type(x)~="table") or (type(x)=="table" and #x ~= self:dim()) then
        error("Expected an array of" .. self:dim() .. " real numbers.")
    end
    local N = self:rangedim()
    local y = terralib.newlist{}
    for i,v in ipairs(self.I) do
        local k = self.invperm[i]
        if Interval.isa(v) then
            y:insert(v(x[k]))
        elseif type(v)=="number" then
            y:insert(v)
        else
            error("Expected a real number or an interval.")
        end
    end
    return vec.new(y)
end

--translate a hypercube with a vector
local translate_cube = function(cube, v, sign)
    local N = cube:rangedim()
    assert(#v==N and "Dimensions are inconsistent.")
    local args = terralib.newlist{}
    for i = 1, N do
        args:insert(cube.I[i] + sign * v[i])
    end
    return Hypercube.new(unpack(args))
end

function Hypercube:__add(other)
    if Hypercube.isa(self) and type(other)=="table" and #other==self:rangedim() then
        return translate_cube(self, other, 1)
    elseif Hypercube.isa(other) and type(self)=="table" and #self==other:rangedim() then
        return translate_cube(other, self, 1)
    else
        error("Wrong input arguments.")
    end
end

function Hypercube:__unm()
    local args = terralib.newlist{}
    for i = 1, self:rangedim() do
        args:insert(-self.I[i])
    end
    return Hypercube.new(unpack(args))
end

function Hypercube:__sub(other)
    if Hypercube.isa(self) and type(other)=="table" and #other==self:rangedim() then
        return translate_cube(self, other, -1)
    elseif Hypercube.isa(other) and type(self)=="table" and #self==other:rangedim() then
        return translate_cube(-other, self, 1)
    else
        error("Wrong input arguments.")
    end
end

function Hypercube:barycentriccoords(y)
    local D = self:dim()
    local N = self:rangedim()
    local x = terralib.newlist{}
    for k = 1, D do
        local i = self.perm[k]
        x:insert(self.I[i]:barycentriccoord(y[i]))
    end
    return vec.new(x)
end

Hypercube.intersection = function(...)

    --check input arguments
    local args = terralib.newlist{...}
    if #args<2 then
        error("Expected two or more hypercubes as input.")
    end
    for i,v in ipairs(args) do
        if not (type(v)=="table" and Hypercube.isa(v)) then
            error("Expected two or more hypercubes as input.")
        end
    end
    for i,v in ipairs(args) do
        if not (v:rangedim()==args[1]:rangedim()) then
            error("Expected hypercubes with range dimension "..tostring(rangedim))
        end
    end

    --compute intersection of two hypercubes
    local get_intersection_two_vars = function(a, b)
        --if a == b then
        --    return a
        --else
            local N = a:rangedim()
            local I = terralib.newlist()
            for i = 1, N do
                local intersection = Interval.intersection(a.I[i], b.I[i])
                if intersection==nil then
                    --no common intersection
                    return nil
                end
                I:insert(intersection)
            end
            return Hypercube.new(unpack(I))
        --end
    end

    --use recursion to compute intersection of multiple hypercubes
    local get_intersection

    get_intersection = function(a, b, ...)
        local args = terralib.newlist{...}
        local t = get_intersection_two_vars(a, b)
        if #args>0 then
            t = get_intersection(t, ...)
        end
        return t
    end

    return get_intersection(...)
end

Hypercube.__mul = function(self, other)
    local cube = Hypercube.intersection(self, other) --intersection type
    if cube then --non-empty intersection
        local I = cube.I
        local N = self:rangedim()
        for i = 1, N do
            if self:issingulardir(i) and not other:issingulardir(i) then
                I[i] = other.I[i]
            elseif other:issingulardir(i) and not self:issingulardir(i) then
                I[i] = self.I[i]
            elseif self:issingulardir(i) and other:issingulardir(i) then
                I[i] = self.I[i]
            else
                error("This branch should be unreachable.")
            end
        end
        return Hypercube.new(unpack(I))
    end
end

Hypercube.__div = function(self, other)
    local cube = Hypercube.intersection(self, other) --intersection type
    if cube then --non-empty intersection
        local I = cube.I
        local N = self:rangedim()
        for i = 1, N do
            if other:issingulardir(i) then
                I[i] = self.I[i]
            else
                I[i] = cube.I[i].a
            end
        end
        return Hypercube.new(unpack(I))
    end
end

Hypercube.mapping = terralib.memoize(function(args)

    local domain = args.domain
    local origin = args.origin

    --check inputs
    if domain==nil then
        error("Expected named argument 'domain'")
    end

    local N = domain:rangedim()
    
    if not (type(domain)=="table" and Hypercube.isa(domain)) then
        error("Expected named argument 'domain' to be a hypercube.")
    end
    if origin~=nil and not (type(origin)=="table" and #origin==N) then
        error("Expected optional named argument 'origin' to be an array of "..N .. " numbers.")
    end

    --generate inverse permutation, and fill A and B with data for linear
    --map: A * X + B, such that [0,1]^N maps to the hypercube
    local A, B = terralib.newlist(), terralib.newlist()
    local A_inv, B_inv = terralib.newlist(), terralib.newlist()
    local D = 0
    
    for i, v in ipairs(domain.I) do
        local o
        if type(v)=="number" then
            if origin~=nil then 
                o = origin[i] 
                if v~=o then
                    error("Expected origin["..i.."] = ".. tostring(v))
                end
            else 
                o = v 
            end
            A:insert(0)
            B:insert(v)
            A_inv:insert(0)
            B_inv:insert(0)
        elseif Interval.isa(v) then
            if origin~=nil then 
                o = origin[i]
            else 
                o = v.a
            end
            local center = 0.5 * (v.a + v.b)
            local signed = (o<=center) and 1 or -1
            A:insert((v.b - v.a) * signed)
            B:insert(o)
            A_inv:insert(signed / (v.b - v.a))
            B_inv:insert(-signed * o / (v.b - v.a))
            D = D + 1
        end
    end

    --dummy struct
    local struct mapping{ }

    --static data
    mapping.ismapping = true
    mapping.domain = domain

    --construct static arrays for linear map 'y = a * x + b'
    --and origin 'o'
    local vec = vector(T,N)
    local map, invmap = {}, {}
    mapping.a = terralib.constant(terralib.new(T[N], A))
    mapping.b = terralib.constant(terralib.new(T[N], B))
    --construct static arrays for linear inverse map 'x = (1/a) y - b/a'
    invmap.a = terralib.constant(terralib.new(T[N], A_inv))
    invmap.b = terralib.constant(terralib.new(T[N], B_inv))

    local perm = domain.perm
    local invperm = domain.invperm

    mapping.metamethods.__apply = terra(self : &mapping, x : ntuple(T, D))
        var y = [mapping.b]
        escape
            for i = 1, D do
                local s = "_"..tostring(i-1)
                local k = perm[i]
                local a, b = A[k], B[k]
                emit quote y[k-1] = tmath.fusedmuladd([T](a), x.[s], [T](b)) end
            end
        end
        return y
    end

    mapping.methods.vol = terra(self : &mapping, x : ntuple(T, D))
        return [mapping.domain:vol()]
    end

    terra mapping:barycentriccoord(y : ntuple(T,N))
        var x : ntuple(T, D)
        escape
            for i = 1, D do
                local k = perm[i]
                local sx = "_"..tostring(i-1)
                local sy = "_"..tostring(k-1)
                local a, b = A_inv[k], B_inv[k]
                emit quote x.[sx] = tmath.fusedmuladd([T](a), y.[sy], [T](b)) end
            end
        end
        return x
    end

    return mapping
end)


local Pyramid = {}
Pyramid.__index = Pyramid;
Pyramid.__metatable = Pyramid;

function Pyramid.isa(t)
    return getmetatable(t) == Pyramid
end

Pyramid.new = function(args)

    local base = args.base
    local apex = args.apex

    --check inputs
    if base==nil or apex==nil then
        error("Expected named arguments 'base' and 'apex'")
    end

    local M = base:dim()+1
    local N = base:rangedim()
    
    if not (type(base)=="table" and Hypercube.isa(base)) then
        error("Expected named argument 'base' to be a hypercube.")
    end
    if not (type(apex)=="table" and #apex==N) then
        error("Expected named argument 'apex' to be an array of "..N .. " numbers.")
    end
    --wrap into a vector if needed
    if not vec.isa(apex) then
        apex = vec.new(apex)
    end

    --dummy struct
    local pyramid = { }

    --static data
    pyramid.base = base
    pyramid.apex = apex

    function pyramid:dim()
        return self.base:dim()+1
    end

    function pyramid:rangedim()
        return self.base:rangedim()
    end

    function pyramid:height()
        local x = base:barycentriccoords(apex)
        local y = base(x)
        return (apex - y):norm()
    end

    function pyramid:vol()
        return self:height() * base:vol() / self:dim()
    end

    return setmetatable(pyramid, Pyramid)
end

function Pyramid:__tostring()
    return "Pyramid {base = "..tostring(self.base) ..", apex = "..tostring(self.apex).."}"
end

Pyramid.decomposition = function(args)
    local cube = args.cube
    local apex = args.apex
    --check inputs
    if cube==nil or apex==nil then
        error("Expected named arguments 'cube' and 'apex'")
    end
    --check cube
    if not Hypercube.isa(cube) then
        error("Expected a hypercube.")
    end
    local D = cube:dim()
    local N = cube:rangedim()
    --check apex
    if type(apex)~="table" or #apex~=N then
        error("Expected an array of "..tostring(N) .. " real numbers.")
    end
    --translate cube 
    local cube = cube - apex
    local apex = apex
    --static variable
    local i = 0
    return function()
        i = i+1
        if i <= D then   
            local k = cube.perm[i]
            local I = table.copy(cube.I)
            if I[k].a==0 then 
                I[k] = I[k].b
            elseif I.b==0 then
                I[k] = I[k].a
            else
                error("The apex should be on the boundary of the product space.")
            end
            local base = Hypercube.new(unpack(I)) + apex
            local P = Pyramid.new{base = base, apex = apex}
            return P
        end
    end
end

Pyramid.mapping = terralib.memoize(function(args)

    local domain = args.domain

    --check inputs
    if domain==nil then
        error("Expected named argument 'domain'.")
    end
    if not (type(domain)=="table" and Pyramid.isa(domain)) then
        error("Expected named argument 'domain' to be a pyramid.")
    end

    local D = domain:dim()
    local N = domain:rangedim()

    local base = terralib.constant(terralib.new(Hypercube.mapping{domain=domain.base}))
    local apex = terralib.constant(terralib.new(T[N], domain.apex))

    --dummy struct
    local struct mapping{ }

    --static data
    mapping.ismapping = true
    mapping.domain = domain

    --convex combination using simd instructions
    local vec = vector(T,N)
    local eval = terra(s : T, a : &vec, b : &vec)
        return (1.-s) * @a + s * @b
    end

    local extractargs = function(...)
        local args = terralib.newlist{...}
        if #args~=D then
            error("Expected ".. tostring(D) .. " input arguments.")
        end
        local x = terralib.newlist{}
        for i=1,D-1 do
            x:insert(args[i])
        end
        local s = args[D]
        return x, s
    end

    mapping.metamethods.__apply = terra(self : &mapping, x : ntuple(T,D-1), s : T)
        var b = base(x)
        var y = eval(s, [&vec](&apex), [&vec](&b))
        var ptr_y  = [ &T[N] ](&y)
        return @ptr_y
    end

    mapping.methods.vol = terra(self : &mapping, x : ntuple(T,D-1), s : T)
        return tmath.pow(s, D-1) * [domain.base:vol()] * [domain:height()] 
    end

    return mapping
end)


local ProductPair = {}
ProductPair.__index = ProductPair;
ProductPair.__metatable = ProductPair;

function ProductPair.isa(t)
    return getmetatable(t) == ProductPair
end

ProductPair.new = function(A, B)

    --check inputs
    if A==nil or B==nil then
        error("Expected named arguments 'A' and 'B'")
    end
    if not (Hypercube.isa(A) and Hypercube.isa(B)) then
        error("Expected named arguments 'A' and 'B' to be of type hypercube.")
    end
    local N = A:rangedim()
    if A:rangedim()~=B:rangedim() then
       error("Range dimensions of A and B are inconsistent.")
    end
    local C = Hypercube.intersection(A, B)
    if C==nil or C:dim()~=0 then
        error("Invalid product pair.")
    end
    local V = A * B
    if V==nil or V:dim()~=N then
        error("Invalid product pair.")
    end

    --dummy struct
    local productpair = { }

    --static data
    productpair.A = A
    productpair.B = B

    function productpair:dim()
        return A:dim(), B:dim()
    end

    function productpair:rangedim()
        return N
    end

    return setmetatable(productpair, ProductPair)
end

function ProductPair:__tostring()
    return "ProductPair {A = "..tostring(self.A) ..", B = "..tostring(self.B).."}"
end

ProductPair.mapping = terralib.memoize(function(args)

    local domain = args.domain
    local origin = args.origin

    --check inputs
    if domain==nil then
        error("Expected named argument 'domain'.")
    end
    if not (type(domain)=="table" and ProductPair.isa(domain)) then
        error("Expected named argument 'domain' to be a 'ProductPair'.")
    end
    local N = domain:rangedim()
    if origin~=nil and not (type(origin)=="table" and #origin==N) then
        error("Expected optional named argument 'origin' to be an array of "..N .. " numbers.")
    end
    --select origin from intersection
    if origin==nil then
        local C = Hypercube.intersection(domain.A, domain.B)
        origin = C.origin
    end

    local D1, D2 = domain:dim()
    local N = domain:rangedim()

    local A = terralib.constant(terralib.new(Hypercube.mapping{domain=domain.A, origin=origin}))
    local B = terralib.constant(terralib.new(Hypercube.mapping{domain=domain.B, origin=origin}))

    --dummy struct
    local struct mapping{
    }

    --static data
    mapping.ismapping = true
    mapping.domain = domain

    mapping.metamethods.__apply = terra(self : &mapping, x_1 : ntuple(T,D1), x_2 : ntuple(T,D2))
        var y_1, y_2 = A(x_1), B(x_2)
        escape
            local I = domain.A.I
            for i=1,N do
                if not Interval.isa(I[i]) then
                    emit quote y_1[i-1] = y_2[i-1] end
                end
            end
        end
        return y_1
    end

    mapping.methods.vol = terra(self : &mapping, x_1 : ntuple(T,D1), x_2 : ntuple(T,D2))
        return A:vol(x_1) * B:vol(x_2)
    end

    return mapping
end)

return {
    Interval = Interval,
    Hypercube = Hypercube,
    Pyramid = Pyramid,
    ProductPair = ProductPair
}