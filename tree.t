-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local base = require("base")
local io = terralib.includec("stdio.h")

local Allocator = alloc.Allocator

local Tree = terralib.memoize(function(T)
    local struct tree
    local Vec = alloc.SmartBlock(tree)
    struct tree(base.AbstractBase) {
        data: T
        son: Vec
    }
    tree:complete()

    tree.staticmethods.new = terra(alloc: Allocator, data: T, nsons: uint64)
        return tree {data, alloc:new(sizeof(tree), nsons)}
    end

    tree.metamethods.__for = function(iter, body)
        local terra go(root: tree): {}
            var sz = root.son:size()
            for i = 0, sz do
                go(root.son(i))
            end
            var data = root.data
            [body(data)]
        end

        return quote
            go(iter)
        end
    end

    return tree
end)

return {
    Tree = Tree
}
