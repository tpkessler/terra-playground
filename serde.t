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

local function istuple(T)
  --[=[
  	Check if a given type is a tuple
  --]=]
  assert(terralib.types.istype(T))
  if T:isunit() then
    return true
  end
  if not T:isstruct() then
    return false
  end
  local entries = T.entries
  -- An empty struct cannot be the empty tuple as we already checked for unit, the empty tuple.
  if #entries == 0 then
    return false
  end
  -- Entries are named _0, _1, ...
  for i = 1, #entries do
	  if entries[i][1] ~= "_" .. tostring(i - 1) then
		  return false
	  end
  end
  return true
end

local function unpacktuple(T)
    --[=[
        Return list of types in given tuple type

        Args:
            tpl: Tuple type

        Returns:
            One-based terra list composed of the types in the tuple

        Examples:
            print(unpacktuple(tuple(int, double))[2])
            -- double
    --]=]

    -- The entries key of a tuple type is a terra list of tables,
    -- where each table stores the index (zero based) and the type.
    -- Hence we can use the map method of a terra list to extract a list
    -- of terra types. For details, see the implementation of the tuples type
    -- https://github.com/terralang/terra/blob/4d32a10ffe632694aa973c1457f1d3fb9372c737/src/terralib.lua#L1762
	assert(istuple(T))
	return T.entries:map(function(e) return e[2] end)
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
  if istuple(func.returntype) then
    ret = unpacktuple(func.returntype)
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
