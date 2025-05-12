-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
require "terralibext"

local base = require("base")
local concepts = require("concepts")
local template = require("template")
local json = setmetatable(
    terralib.includec("json-c/json.h"),
    {
        __index = function(self, key)
            return rawget(self, "json_object_" .. key) or rawget(self, key)
        end
    }
)
local OS = require("ffi").os
if OS == "Linux" then
    terralib.linklibrary("libjson-c.so")
else
    terralib.linklibrary("libjson-c.dylib")
end


local struct json_object {
    data: &json.json_object
    is_owner: bool
}
json_object.metamethods.__typename = function() return "JSON" end

base.AbstractBase(json_object)

json_object.staticmethods.new = terra()
    return json_object {json.new_object(), true}
end

terra json_object:__dtor()
    if self.is_owner then
        json.put(self.data)
    end
end

terra json_object:tostring()
    return json.to_json_string_ext(self.data, --[[JSON_C_TO_STRING_PRETTY = ]] 2)
end

-- Add

terraform json_object:set(name: rawstring, field: json_object)
    json.object_add(self.data, name, field.data)
end

terraform json_object:set(name: rawstring, field: double)
    json.object_add(self.data, name, json.new_double(field))
end

terraform json_object:set(name: rawstring, field: int32)
    json.object_add(self.data, name, json.new_int(field))
end

terraform json_object:set(name: rawstring, field: int64)
    json.object_add(self.data, name, json.new_int64(field))
end

terraform json_object:set(name: rawstring, field: bool)
    json.object_add(self.data, name, json.new_boolean(field))
end

terraform json_object:set(name: rawstring, field: rawstring)
    json.object_add(self.data, name, json.new_string(field))
end

terra json_object:get(name: rawstring)
    return json_object {json.object_get(self.data, name), false}
end

local convert = template.Template:new("convert")
convert:adddefinition{
    [template.paramlist.new({concepts.Any}, {1}, {0})] = function(T)
        local lookup = {
            [double] = "double",
            [int] = "int",
            [int64] = "int64",
            [rawstring] = "string",
            [bool] = "boolean",
        }
        local suffix = assert(lookup[T], "Cannot convert JSON into " .. tostring(T))
        return terra(obj: &json_object)
            return [ json["get_" .. suffix] ](obj.data)
        end
    end
}

json_object.metamethods.__cast = function(from, to, exp)
    local _, getter = assert(convert(to))
    return quote var obj = [exp] in getter(&obj) end
end

return {
    json_object = json_object,
}
