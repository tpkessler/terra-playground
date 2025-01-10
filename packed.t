-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local base = require("base")
local concepts = require("concepts")

import "terraform"

local SparsePackedFactory = terralib.memoize(function(T, I, M, K)
    local struct sparse_packed {
        Ap: T[M * K]
        loc: I[M * K]
        col: I[K]
        nnz: I[K]
    }
    function sparse_packed.metamethods.__typename(Self)
        return (
            (
                "SparsePacked(%s, %s, %d, %d)"
            ):format(tostring(T), tostring(I), M, K)
        )
    end
    base.AbstractBase(sparse_packed)
    sparse_packed.traits.eltype = T
    sparse_packed.traits.issparse = true
    sparse_packed.traits.Rows = M
    sparse_packed.traits.Cols = K

    local Integer = concepts.Integer
    terraform sparse_packed:pack(
        A: &CSR, rowstart: J, colstart: J
    ) where {CSR, J: Integer}
            var i1 = 0
            var i2 = 0
            for m = 0, M do
                for k = 0, K do
                    self.Ap[k + K * m] = 0
                    self.loc[k + K * m] = 0
                end
            end
            for k = 0, K do
                self.col[k] = 0
                self.nnz[k] = 0
                var cols = 0
                for m = 0, M do
                    var i = rowstart + m
                    if i >= A.rows then
                        break
                    end
                    var data: T
                    var found_entry = false
                    for idx = A.rowptr(i), A.rowptr(i + 1) do
                        var j = A.col(idx)
                        if j == colstart + k then
                            data = A.data(idx)
                            found_entry = true
                            break
                        end
                    end
                    if found_entry then
                        self.Ap[i1] = data
                        self.loc[i1] = m
                        i1 = i1 + 1
                        cols = cols + 1
                    end
                end
                if cols ~= 0 then
                    self.col[i2] = k
                    self.nnz[i2] = cols
                    i2 = i2 + 1
                end
            end
        end

    assert(concepts.SparsePacked(T)(sparse_packed))
    return sparse_packed
end)

local DensePackedFactory = terralib.memoize(function(T, M, K)
    local struct dense_packed {
        A: T[M * K]
    }
    function dense_packed.metamethods.__typename(Self)
        return (
            (
                "DensePacked(%s, %d, %d)"
            ):format(tostring(T), M, K)
        )
    end
    base.AbstractBase(dense_packed)
    dense_packed.traits.eltype = T
    dense_packed.traits.isdense = true
    dense_packed.traits.Rows = M
    dense_packed.traits.Cols = K

    local Matrix = concepts.Matrix(T)
    local Integer = concepts.Integer
    terraform dense_packed:pack(
        A: &Mat, rowstart: J, colstart: J
    ) where {Mat: Matrix, J: Integer}
        var rows = A:rows()
        var cols = A:cols()
        for m = 0, M do
            var i = rowstart + m
            for k = 0, K do
                var j = colstart + k
                var data = [T](0)
                if i < rows and j < cols then
                    data = A:get(i, j)
                end
                self.A[k + K * m] = data
            end
        end
    end

    terraform dense_packed:unpack(
        A: &Mat, rowstart: J, colstart: J
    ) where {Mat: Matrix, J: Integer}
        var rows = A:rows()
        var cols = A:cols()
        for m = 0, M do
            var i = rowstart + m
            for k = 0, K do
                var j = colstart + k
                var data = [T](0)
                if i < rows and j < cols then
                    A:set(i, j, self.A[k + K * m])
                end
            end
        end
    end

    assert(concepts.DensePacked(T)(dense_packed))
    return dense_packed
end)

return {
    SparsePackedFactory = SparsePackedFactory,
    DensePackedFactory = DensePackedFactory,
}
