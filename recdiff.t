-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concepts = require("concepts")
local dvector = require("dvector")
local dmatrix = require("dmatrix")
local qr = require("qr")
local range = require("range")
local svector = require("svector")

import "terraform"

local concept RecDiff(T) where {T: concepts.Number}
    local Integral = concepts.Integer
    Self.traits.ninit = concepts.traittag
    Self.traits.depth = concepts.traittag
    Self.traits.eltype = T
    local Stack = concepts.Stack(T)
    terra Self:getcoeff(n: Integral, y: &Stack): {} end
    terra Self:getinit(y0: &Stack): {} end
end

local Real = concepts.Real
local Vector = concepts.Vector
local terraform olver(alloc, rec: &R, yn: &V)
    where {R: RecDiff(Real), V: Vector(Real)}
    var y0 = [svector.StaticVector(R.traits.eltype, R.traits.ninit)].zeros()
    var nmax = yn:size()
    var n0 = y0:size()
    var dim: int64 = nmax - n0
    var sys = [dmatrix.DynamicMatrix(R.traits.eltype)].zeros(alloc, dim, dim)
    var rhs = [dvector.DynamicVector(R.traits.eltype)].zeros(alloc, dim)
    var hrf = [dvector.DynamicVector(R.traits.eltype)].zeros(alloc, dim)
    var y = [svector.StaticVector(R.traits.eltype, R.traits.depth + 1)].zeros()
    for i = 0, dim do
        var n = n0 + i
        rec:getcoeff(n, &y)
        for offset = 0, [R.traits.depth] do
            var j = i + offset - [R.traits.depth] / 2
            if j >= 0 and j < dim then
                sys(i, j) = y:get(offset)
            end
        end
        rhs:set(i, y:get([R.traits.depth]))
    end
    rec:getinit(&y0)
    for i = 0, n0 do
        rec:getcoeff(n0 + i, &y)
        var r = rhs:get(i)
        for j = i, n0 do
            r = r - y:get(j - i) * y0:get(j)
        end
        rhs:set(i, r)
    end
    var qr = [qr.QRFactory(sys.type, rhs.type)].new(&sys, &hrf)
    qr:factorize()
    qr:solve(false, &rhs)
    for i = 0, n0 do
        yn:set(i, y0:get(i))
    end
    for i = n0, nmax do
        yn:set(i, rhs:get(i - n0))
    end
end

return {
    RecDiff = RecDiff,
    olver = olver,
}
