local operator = require("operator")
local concept = require("concept")
local template = require("template")
local err = require("assert")
local vecbase = require("vector_base")

local Bool = concept.Bool
local UInteger = concept.UInteger
local Number = concept.Number
local Vector = vecbase.Vector

local Matrix = concept.AbstractInterface:new("Matrix")
Matrix:inheritfrom(operator.Operator)
Matrix:addmethod{
    set = {UInteger, UInteger, Number} -> {},
    get = {UInteger, UInteger} -> {Number},
    fill = Number -> {},
    clear = {} -> {},
    copy = {Bool, &Matrix} -> {},
    swap = {Bool, &Matrix} -> {},
    scal = Number -> {},
    axpy = {Number, Bool, &Matrix} -> {},
    dot = {Bool, &Matrix} -> Number,
    mul = {Number, Number, Bool, &Matrix, Bool, &Matrix} -> {},
}

local function MatrixBase(M)
    M.templates.apply = template.Template:new("apply")
    M.templates.apply[{&M.Self, Bool, Number, &Vector, Number, &Vector} -> {}]
    = function(Self, B, S1, V1, S2, V2)
        local terra apply(self: Self, trans: B, alpha: S1, x: V1, beta: S2, y: V2)
            if trans then
                var ns = self:rows()
                var ms = self:cols()
                var nx = x:size()
                var ny = y:size()
                err.assert(ms == ny and ns == nx)
                for i = 0, ms do
                    var res = [Self.eltype](0)
                    for j = 0, ns do
                        res = res + self:get(j, i) * x:get(j)
                    end
                    y:set(i, beta * y:get(i) + alpha * res)
                end
            else
                var ns = self:rows()
                var ms = self:cols()
                var nx = x:size()
                var ny = y:size()
                err.assert(ns == ny and ms == nx)
                for i = 0, ns do
                    var res = [Self.eltype](0)
                    for j = 0, ms do
                        res = res + self:get(i, j) * x:get(j)
                    end
                    y:set(i, beta * y:get(i) + alpha * res)
                end
            end
        end
    end
    assert(operator.Operator(M))
    operator.Operator:addimplementations{M}
    
    M.templates.fill = template.Template:new("fill")
    M.templates.fill[{&M.Self, Number} -> {}] = function(Self, S)
        local terra fill(self: Self, a: S)
            var rows = self:rows()
            var cols = self:cols()
            for i = 0, rows do
                for j = 0, cols do
                    self:set(i, j, a)
                end
            end
        end
        return fill
    end

    M.templates.clear = template.Template:new("clear")
    M.templates.clear[&M.Self -> {}] = function(Self)
        local terra clear(self: Self)
            self:fill(0)
        end
        return clear
    end

    M.templates.copy = template.Template:new("copy")
    M.templates.copy[{&M.Self, Bool, &Matrix} -> {}] = function(Self, B, M)
        local terra copy(self: Self, trans: B, other: M)
            var ns = self:rows()
            var ms = self:cols()
            var no = other:rows()
            var mo = other:cols()
            if trans then
                err.assert(ns == mo and ms == no)
                for i = 0, ns do
                    for j = 0, ms do
                        self:set(i, j, other:get(j, i))
                    end
                end
            else
                err.assert(ns == no and ms == mo)
                for i = 0, ns do
                    for j = 0, ms do
                        self:set(i, j, other:get(i, j))
                    end
                end
            end
        end
        return copy
    end

    M.templates.swap = template.Template:new("swap")
    M.templates.swap[{&M.Self, Bool, &Matrix} -> {}] = function(Self, B, M)
        local terra swap(self: Self, trans: B, other: M)
            var ns = self:rows()
            var ms = self:cols()
            var no = other:rows()
            var mo = other:cols()
            if trans then
                err.assert(ns == mo and ms == no)
                for i = 0, ns do
                    for j = 0, ms do
                        var s = self:get(i, j)
                        var o = other:get(j, i)
                        self:set(i, j, o)
                        other:set(j, i, s)
                    end
                end
            else
                err.assert(ns == no and ms == mo)
                for i = 0, ns do
                    for j = 0, ms do
                        var s = self:get(i, j)
                        var o = other:get(i, j)
                        self:set(i, j, o)
                        other:set(i, j, s)
                    end
                end
            end
        end
        return swap
    end

    M.templates.scal = template.Template:new("scal")
    M.templates.scal[{&M.Self, Number} -> {}] = function(Self, S)
        local terra scal(self: Self, a: S)
            var ns = self:rows()
            var ms = self:cols()
            for i = 0, ns do
                for j = 0, ms do
                    self:set(i, j, a * self:get(i, j))
                end
            end
        end
        return scal
    end

    M.templates.axpy = template.Template:new("axpy")
    M.templates.axpy[{&M.Self, Number, Bool, &Matrix} -> {}] = function(Self, S, B, M)
        local terra axpy(self: Self, a: S, trans: B, other: M)
            var ns = self:rows()
            var ms = self:cols()
            var no = other:rows()
            var mo = other:cols()
            if trans then
                err.assert(ns == mo and ms == no)
                for i = 0, ns do
                    for j = 0, ms do
                        self:set(i, j, self:get(i, j) + a * other:get(j, i))
                    end
                end
            else
                err.assert(ns == no and ms == mo)
                for i = 0, ns do
                    for j = 0, ms do
                        self:set(i, j, self:get(i, j) + a * other:get(i, j))
                    end
                end
            end
        end
        return axpy
    end

    M.templates.dot = template.Template:new("dot")
    M.templates.dot[{&M.Self, Bool, &Matrix} -> Number] = function(Self, B, M)
        local terra dot(self: Self, trans: B, other: M)
            var ns = self:rows()
            var ms = self:cols()
            var no = other:rows()
            var mo = other:cols()
            if trans then
                err.assert(ns == mo and ms == no)
                var sum = self:get(0, 0) * other:get(0, 0)
                for i = 0, ns do
                    for j = 0, ms do
                        if i > 0 or j > 0 then
                            sum = sum + self:get(i, j) * other:get(j, i)
                        end
                    end
                end
                return sum
            else
                err.assert(ns == no and ms == mo)
                var sum = self:get(0, 0) * other:get(0, 0)
                for i = 0, ns do
                    for j = 0, ms do
                        if i > 0 or j > 0 then
                            sum = sum + self:get(i, j) * other:get(i, j)
                        end
                    end
                end
                return sum
            end
        end
        return dot
    end
    M.templates.mul = template.Template:new("mul")
    M.templates.mul[{&M.Self, Number, Number, Bool, &Matrix, Bool, &Matrix} -> {}]
    = function(Self, S1, S2, B1, M1, B2, M2)
        local terra mul(self: Self, beta: S1, alpha: S2, atrans: B1, a: M1, btrans: B2, b: M2)
            -- TODO Write implementation for all cases
            if atrans then
            else
            end
        end
        return mul
    end
    
    assert(Matrix(M))
    Matrix:addimplementations{M}
end

return {
    Matrix = Matrix,
    MatrixBase = MatrixBase,
}
