local alloc = require("alloc")
local err = require("assert")
local complex = require("complex")
local blas = require("blas")

local complexFloat = complex(float)[1]
local complexDouble = complex(double)[1]

local function is_blas_type(T)
    local blas_type = {float, double, complexFloat, complexDouble}
    for _, B in pairs(blas_type) do
        if B == T then
            return true
        end
    end

    return false
end

local Vector = function(T, A)
    A = A or alloc.Default
    alloc.Allocater:isimplemented(A)

    local struct vector{
        data: &T
        size: int64
        inc: int64
        buf: int64
        mem: A
    }

    local DEFAULT_BUF_SIZE = 128

    local terra new(size: int64)
        var mem: A
        var buf = size + DEFAULT_BUF_SIZE
        var data = [&T](mem:alloc(sizeof(T) * buf))
        return vector {data, size, 1, buf, mem}
    end

    terra vector:free()
        self.mem:free(self.data)
    end

    terra vector:size()
        return self.size
    end

    terra vector:inc()
        return self.inc
    end

    terra vector:data()
        return self.data
    end

    terra vector:get(i: int64)
        err.assert(i >= 0)
        err.assert(i < self:size())
        return self.data[self.inc * i]
    end

    terra vector:set(i: int64, a: T)
        err.assert(i < self:size())
        self.data[self.inc * i] = a
    end

    terra vector:push(a: T): {}
        var idx = self.inc * self.size
        if self.buf > idx then
            self.data[idx] = a
            self.size = self.size + 1
        else
            var new_buf = 2 * self.buf + 1
            var new_data = [&T](self.mem:alloc(sizeof(T) * new_buf))
            for i = 0, self.buf do
                new_data[i] = self.data[i]
            end
            self.mem:free(self.data)
            self.buf = new_buf
            self.data = new_data
            self:push(a)
        end
    end

    terra vector:pop()
        err.assert(self:size() > 0)
        var x = self:get(self:size() - 1)
        self.size = self.size - 1
        return x
    end

    terra vector:fill(a: T)
        for i = 0, self:size() do
            self:set(i, a)
        end
    end

    terra vector:clear()
        self:fill(0)
    end

    terra vector:copy(y: vector)
        err.assert(self:size() == y:size())

        for i = 0, self:size() do
            self:set(i, y:get(i))
        end
    end

    terra vector:subview(size: int64, offset: int64, inc: int64)
        -- TODO Check size and offset
        var new_data = self.data + offset * self.inc
        var new_size = size
        var new_inc = inc * self.inc
        var new_buf = self.buf
        var new_mem = self.mem
        return vector {new_data, new_size, new_inc, new_buf, new_mem}
    end

    terra vector:getblasinfo()
        return self:size(), self:data(), self:inc()
    end

    if is_blas_type(T) then
        terra vector:swap(x: vector)
            var x_size, x_data, x_inc = x:getblasinfo()
            var y_size, y_data, y_inc = self:getblasinfo()

            err.assert(x_size == y_size)

            blas.swap(x_size, x_data, x_inc, y_data, y_inc)
        end

        terra vector:scal(a: T)
            var x_size, x_data, x_inc = self:getblasinfo()

            blas.scal(x_size, a, x_data, x_inc)
        end
        
        terra vector:axpy(a: T, x: vector)
            var x_size, x_data, x_inc = x:getblasinfo()
            var y_size, y_data, y_inc = self:getblasinfo()

            err.assert(x_size == y_size)

            blas.axpy(x_size, a, x_data, x_inc, y_data, y_inc)
        end

        terra vector:dot(x: vector)
            var x_size, x_data, x_inc = x:getblasinfo()
            var y_size, y_data, y_inc = x:getblasinfo()

            err.assert(x_size == y_size)

            return blas.dot(x_size, x_data, x_inc, y_data, y_inc)
        end

        terra vector:nrm2()
            var x_size, x_data, x_inc = self:getblasinfo()

            return blas.nrm2(x_size, x_data, x_inc)
        end

        terra vector:asum()
            var x_size, x_data, x_inc = self:getblasinfo()

            return blas.asum(x_size, x_data, x_inc)
        end

        terra vector:iamax()
            var x_size, x_data, x_inc = self:getblasinfo()

            return blas.iamax(x_size, x_data, x_inc)
        end
    end

    vector.metamethods.__for = function(iter, body)
        return quote
            var size = iter:size()
            for i = 0, size do
                var data = iter:get(i)
                [body(data)]
            end
        end
    end

    local from = macro(
        function(...)
            local arg = {...}
            local vec = symbol(vector)
            local push = terralib.newlist()
            for _, v in ipairs(arg) do
                push:insert(quote [vec]:push(v) end)
            end

            return quote
                       var [vec] = new(0)
                       [push]     
                   in
                       [vec]
                   end
        end)

    local terra like(x: vector)
        var size = x:size()
        var y = new(size)

        return y
    end

    local terra zeros_like(x: vector)
        var y = like(x)
        y:clear()

        return y
    end

    local self = {type = vector,
                  new = new,
                  from = from,
                  like = like,
                  zeros_like = zeros_like
                 }

    return self
end

Vector = terralib.memoize(Vector)

return Vector
