-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local base = require("base")
local range = require("range")

local BinaryTree = terralib.memoize(function(T)
    local struct tree
    local stree = alloc.SmartObject(tree)
    struct tree {
        data: T
        parent: &tree
        left: stree
        right: stree
    }
    function tree.metamethods.__typename(self)
        return ("BinaryTree(%s)"):format(tostring(T))
    end
    tree:complete()
    base.AbstractBase(tree)

    terra tree.staticmethods.new(A: alloc.Allocator, data: T, parent: &tree)
        var t = stree.new(&A)
        t.data = data
        t.parent = parent
        t.left = stree.frombuffer(1, nil)
        t.right = stree.frombuffer(1, nil)
        return t
    end

    local childs = {["left"] = symbol(T), ["right"] = symbol(T)}
    for key, sym in pairs(childs) do
        tree.methods["grow_" .. key] = (
            terra(self: &tree, A: alloc.Allocator, [sym])
                self.[key] = tree.new(A, [sym], self)
            end
        )
    end
    terra tree:grow(A: alloc.Allocator, [childs.left], [childs.right])
        escape
            for key, sym in pairs(childs) do
                emit `self:["grow_" .. key](A, [sym])
            end
        end
    end

    local struct iterator {
        current: &tree
    }

    terra iterator:getvalue()
        return self.current.data
    end

    terra iterator:isvalid()
        return self.current ~= nil
    end

    terra iterator:next()
        var current = self.current
        if current.right.ptr ~= nil then
            current = current.right.ptr
            while current.left.ptr ~= nil do
                current = current.left.ptr
            end
        else
            while current ~= nil do
                var temp = current
                current = current.parent
                if current == nil or current.left.ptr == temp then
                    break
                end
            end
        end
        self.current = current
    end

    terra tree:getiterator()
        var current = self
        if current ~= nil then
            while current.left.ptr ~= nil do
                current = current.left.ptr
            end
        end
        return iterator {current}
    end

    range.Base(tree, iterator)

    return tree
end)

return {
    BinaryTree = BinaryTree
}
