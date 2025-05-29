require "terralibext"

local lookup = setmetatable(
    {_id = 0},
    {__index = function(self, T)
            local id = rawget(self, T)
            if id then
                return id
            else
                local globid = rawget(self, "_id")
                globid = globid + 1
                rawset(self, T, globid)
                rawset(self, "_id", globid)
                return globid
            end
        end
    }
)

local function cache(T)
    return lookup[T]
end

local function base(T)
    local rttientry = T.entries[1] or {}
    if rttientry.field ~= "_typeid" and rttientry ~= int64 then
        T.entries:insert(1, {field = "_typeid", type = int64})
    end

    T.typeid = cache(T)

    terralib.ext.addmissing.__init(T)
    local oldinit = T.methods.__init
    T.methods.__init = terra(self: &T)
        escape
            if oldinit then
                emit quote oldinit(self) end
            end
        end
        self._typeid = [T.typeid]
    end
end

local terra typeid(x: &opaque)
    var id = @[&int64](x)
    return id
end

local dynamic_cast = terralib.memoize(function(T)
    local refid = (
        assert(T.typeid, "RTTI: Cannot find typeid on type " .. tostring(T))
    )
    return terra(x: &opaque)
        var id = typeid(x)
        if id == refid then
            return [&T](x)
        else
            return nil
        end
    end
end)

return {
    base = base,
    cache = cache,
    typeid = typeid,
    dynamic_cast = dynamic_cast,
}
