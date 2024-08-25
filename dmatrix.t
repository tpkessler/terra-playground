local alloc = require("alloc")
local base = require("base")
local concept = require("concept")
local matrix = require("matrix")
local err = require("assert")
local fun = require("fun")
local tupl = require("tuple")

local Allocator = alloc.Allocator
local size_t = uint64

local DynamicMatrix = terralib.memoize(function(T)
    local S = alloc.SmartBlock(T)
    
    local struct M(base.AbstractBase){
        data: S
        rows: size_t
        cols: size_t
        ld: size_t
    }
    M.eltype = T

    terra M:rows()
        return self.rows
    end

    terra M:cols()
        return self.cols
    end

    terra M:get(i: size_t, j: size_t)
        err.assert(i < self:rows() and j < self:cols())
        return self.data:get(j + self.ld * i)
    end

    terra M:set(i: size_t, j: size_t, a: T)
        err.assert(i < self:rows() and j < self:cols())
        self.data:set(j + self.ld * i, a)
    end

    matrix.MatrixBase(M)

    if concept.BLASNumber(T) then
        terra M:getblasdenseinfo()
            return self:rows(), self:cols(), self.data.ptr, self.ld
        end
        local matblas = require("matrix_blas_dense")
        matblas.BLASDenseMatrixBase(M)
    end

    terra M.staticmethods.new(alloc: Allocator, rows: size_t, cols: size_t)
        return M {alloc:allocate(sizeof(T), rows * cols), rows, cols, cols}
    end

    terra M.staticmethods.like(alloc: Allocator, m: &M)
        return M.new(alloc, m:rows(), m:cols())
    end

    terra M.staticmethods.all(alloc: Allocator, rows: size_t, cols: size_t, a: T)
        var m = M.new(alloc, rows, cols)
        for i = 0, rows do
            for j = 0, cols do
                m:set(i, j, a)
            end
        end
        return m
    end

    terra M.staticmethods.zeros(alloc: Allocator, rows: size_t, cols: size_t)
        return M.all(alloc, rows, cols, 0)
    end

    terra M.staticmethods.all_like(alloc: Allocator, m: &M, a: T)
        return M.all(alloc, m:rows(), m:cols(), a)
    end

    terra M.staticmethods.zeros_like(alloc: Allocator, m: &M)
        return M.all(alloc, m:rows(), m:cols(), 0)
    end

    M.staticmethods.from = macro(function(alloc, tabl)
        local dim = tupl.tensortuple(tabl.tree.type)
        assert(#dim == 2)
        local rows, cols = unpack(dim)

        local m = symbol(M)
        local loop = terralib.newlist()

        local function get(tpl, i, j)
            return `tpl.["_" .. tostring(i)].["_" .. tostring(j)]
        end
        for i = 0, rows - 1 do
            for j = 0, cols - 1 do
                loop:insert(quote [m]:set(i, j, [get(tabl, i, j)]) end)
            end
        end
        return quote
            var [m] = M.new(alloc, rows, cols)
            [loop]
        in
            [m]
        end
    end)

    return M
end)

return {
    DynamicMatrix = DynamicMatrix
}
