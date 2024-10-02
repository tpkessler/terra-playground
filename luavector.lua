-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local vector = {};

vector.__index = vector;
vector.__metatable = vector;

function vector.new(v)
    local n = #v
    if type(v)=="table" and (n==1 or n==2 or n==3) then
        return setmetatable(v, vector)
    else
        error("Expexted an array of one or more real numbers as arguments.")
    end
end

function vector.isa(v)
    return getmetatable(v) == vector
end

function vector:dim()
    return #self
end

function vector:__add(other)
    if self:dim()==1 then
        return vector.new{self[1] + other[1]}
    elseif self:dim()==2 then
        return vector.new{self[1] + other[1], self[2] + other[2]}
    elseif self:dim()==3 then
        return vector.new{self[1] + other[1], self[2] + other[2], self[3] + other[3]}
    end
end

function vector:__sub(other)
	if self:dim()==1 then
        return vector.new{self[1] - other[1]}
    elseif self:dim()==2 then
        return vector.new{self[1] - other[1], self[2] - other[2]}
    elseif self:dim()==3 then
        return vector.new{self[1] - other[1], self[2] - other[2], self[3] - other[3]}
    end
end

function vector:__mul(other)
    local function ax(a, x)
        if x:dim()==1 then
            return vector.new{a * x[1]}
        elseif x:dim()==2 then
            return vector.new{a * x[1], a * x[2]}
        elseif x:dim()==3 then
            return vector.new{a * x[1], a * x[2], a * x[3]}
        end
    end
    if type(self) == "number" then
        return ax(self, other)
    elseif type(other)=="number" then
        return ax(other,self)
    end
end

function vector:__mod(other)
    if self:dim()==1 then
        return 0
    elseif self:dim()==2 then
        return self[1] * other[2] - self[2] * other[1]
    elseif self:dim()==3 then
        return vector.new{self[2] * other[3] - self[3] * other[2], self[3] * other[1] - self[1] * other[3], self[1] * other[2] - self[2] * other[1]}
    end
end

function vector:__unm()
    if self:dim()==1 then
        return vector.new{-self[1]}
    elseif self:dim()==2 then
        return vector.new{-self[1], -self[2]}
    elseif self:dim()==3 then
        return vector.new{-self[1], -self[2], -self[3]}
    end
end

function vector:__eq(other)
    if self:dim() ~=other:dim() then
        return false
    end
    for i=1,self:dim() do
	    if self[i] ~= other[i] then
            return false
        end
    end
    return true
end

function vector:norm()
    local l2 = 0
    for i=1,self:dim() do
	    l2 = l2 + self[i]*self[i]
    end
	return math.sqrt(l2)
end

function vector:__tostring()
    if self:dim()==1 then
        return string.format("(%g)", self[1]);
    elseif self:dim()==2 then
        return string.format("(%g, %g)", self[1], self[2]);
    elseif self:dim()==3 then
        return string.format("(%g, %g, %g)", self[1], self[2], self[3]);
    end
end

-- 2D vectors
local v = vector.new{3,4}
local w = vector.new{3,2}
--test if isa vector
assert(vector.isa(v))
--test dimension
assert(v:dim()==2 and w:dim()==2)
--test addition
assert(v + w == vector.new{6,6})
--test negation
assert(-v == vector.new{-v[1],-v[2]})
--test multiplication
assert(2 * v == vector.new{2*v[1], 2*v[2]})
assert(v * 2 == vector.new{2*v[1], 2*v[2]})
--test cross product
assert(v % w == -6)
--test length
assert(v:norm()==5)


--3D vectors
local v = vector.new{3,4,5}
local w = vector.new{3,2,1}
--test if isa vector
assert(vector.isa(v))
--test dimension
assert(v:dim()==3 and w:dim()==3)
--test addition
assert(v + w == vector.new{6,6,6})
--test negation
assert(-v == vector.new{-v[1],-v[2],-v[3]})
--test multiplication
assert(2 * v == vector.new{2*v[1], 2*v[2], 2*v[3]})
assert(v * 2 == vector.new{2*v[1], 2*v[2], 2*v[3]})
--test cross product
assert(v % w == vector.new{-6,12,-6})
--test length
assert(v:norm()==math.sqrt(50))

return vector