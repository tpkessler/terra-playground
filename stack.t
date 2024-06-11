local alloc = require("alloc")
local err = require("assert")
local interface = require("interface")


local function Stacker(T, I)
    I = I or int64
    return interface.Interface:new{
            size = {} -> I,
            set = {I, T} -> {},
            get = I -> T
        }
end

local function DynamicStack(T, I, A)
    A = A or alloc.Default
    alloc.Allocater:isimplemented(A)

    local struct stack{
        data: &T
        is_owner: bool
        size: int64
        buf: int64
        mem: A
    }

    local DEFAULT_BUF_SIZE = 16

    local terra new(size: int64)
        var mem: A
        var buf = size + DEFAULT_BUF_SIZE
        var data = [&T](mem:alloc(sizeof(T) * buf))
        var is_owner = true
        return stack {data, is_owner, size, buf, mem}
    end

    terra stack:free()
        if self.is_owner then
            self.mem:free(self.data)
        end
    end
    
    terra stack:size()
        return self.size
    end

    terra stack:get(i: int64)
        err.assert(i >= 0)
        err.assert(i < self:size())
        return self.data[i]
    end

    terra stack:set(i: int64, a: T)
        err.assert(i >= 0)
        err.assert(i < self:size())
        self.data[i] = a
    end

    local Stacker = Stacker(T, I)
    Stacker:isimplemented(stack)

    terra stack:push(a: T): {}
        err.assert(self.is_owner)
        
        var idx = self.size
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

    terra stack:pop()
        err.assert(self.is_owner)
        err.assert(self:size() > 0)
        var x = self:get(self:size() - 1)
        self.size = self.size - 1
        return x
    end

    terra stack:slice(size: int64, offset:int64)
        err.assert(size + offset <= self:size())
        var new_data = self.data + offset
        var new_is_owner = false
        var new_size = size
        var new_buf = 0
        var new_mem = self.mem

        return stack {new_data, new_is_owner, new_size, new_buf, new_mem}
    end

    local terra from_buffer(size: int64, data: &T)
        return stack {data, false, size, 0, @[&A](nil)}
    end

    local static_methods = {
        new = new,
        frombuffer = from_buffer,
    }

    stack.metamethods.__getmethod = function(Self, method)
        return stack.methods[method] or static_methods[method]
    end

    return stack
end

return {
    Stacker = Stacker,
    DynamicStack = DynamicStack
}

