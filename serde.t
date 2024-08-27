local tuple = require("tuple")

local function get_local_vars()
  --[=[
  	Return a key-value list of all lua variables available in the current scope.
  --]=]
  local upvalues = {}
  local thread = 0 -- Index of scope
  local failure = 0 -- It might fail on the inner scope, so break if this larger than 1.
  while true do
    thread = thread + 1
    local index = 0 -- Index of local variables in scope
    while true do
      index = index + 1
      -- The number of scopes is not known before, so we have to iterate
      -- until debug.getlocal throws an error
      local ok, name, value = pcall(debug.getlocal, thread, index)
      if ok and name ~= nil then
        upvalues[name] = value
      else
        if index == 1 then -- no variables in scope
          failure = failure + 1
        end
        break
      end
    end
    if failure > 1 then
      break
    end
  end
  return upvalues
end

local function get_terra_types()
  --[=[
  	Return key-value list of a terra types available in the current scope.
  --]=]
  local types = {}
  -- First iterate over globally defined types. This includes primitive types
  for k, v in pairs(_G) do
    if terralib.types.istype(v) then
      types[k] = v
      types[tostring(v)] = v
    end
  end
  -- Terra structs or type aliases can be defined with the local keyword,
  -- so we have to iterate over the local lua variables too.
  local upvalues = get_local_vars()
  for k, v in pairs(upvalues) do
    if terralib.types.istype(v) then
      types[k] = v
      types[tostring(v)] = v
    end
  end
  return types
end

local function striplist(a)
  --[=[
  	Convert a terra list into a lua table.
  --]=]
  local b = {}
  for k, v in pairs(a) do
    b[k] = v
  end
  return b
end

local serpent = require("serpent")
local function serialize_table(tab)
	return serpent.dump(tab, {sortkeys = true})
end
local function deserialize_table(str)
	return serpent.load(str)
end

local function serialize_pointertofunction(func)
  assert(terralib.types.istype(func) and func:ispointertofunction())
  func = func.type
  local param = striplist(func.parameters)
  local ret
  if tuple.istuple(func.returntype) then
    ret = tuple.unpacktuple(func.returntype)
    ret = striplist(ret)
  else
    ret = {func.returntype}
  end
  local func_array = {["param"] = param, ["ret"] = ret}
  return serialize_table(func_array)
end

local function deserialize_types(context, a)
  local gettype = function(str)
	  local T
	  if str:match("&") then
		local Tp = context[str:sub(2,-1)]
		T = terralib.types.pointer(Tp)
	  else
		T = context[str]
	  end
	  return T
  end
  local b = terralib.newlist(a)
  return b:map(function(t) return gettype(t) end)
end

local function deserialize_pointertofunction(str)
  local ok, obj = deserialize_table(str)
  assert(ok)
  local type_list = get_terra_types()
  local param = deserialize_types(type_list, obj.param)
  local ret = deserialize_types(type_list, obj.ret)
  return param -> ret
end

return {
	serialize_table = serialize_table,
	deserialize_table = deserialize_table,
	serialize_pointertofunction = serialize_pointertofunction,
	deserialize_pointertofunction = deserialize_pointertofunction,
}
