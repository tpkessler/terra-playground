local function get_upvalues()
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

local function get_types()
  local types = {}
  for k, v in pairs(_G) do
    if terralib.types.istype(v) then
      types[k] = v
      types[tostring(v)] = v
    end
  end
  local upvalues = get_upvalues()
  for k, v in pairs(upvalues) do
    if terralib.types.istype(v) then
      types[k] = v
      types[tostring(v)] = v
    end
  end
  return types
end

local function tuple_type_to_list(tpl)
    --[=[
        Return list of types in given tuple type

        Args:
            tpl: Tuple type

        Returns:
            One-based terra list composed of the types in the tuple

        Examples:
            print(tuple_type_to_list(tuple(int, double))[2])
            -- double
    --]=]

    -- The entries key of a tuple type is a terra list of tables,
    -- where each table stores the index (zero based) and the type.
    -- Hence we can use the map method of a terra list to extract a list
    -- of terra types. For details, see the implementation of the tuples type
    -- https://github.com/terralang/terra/blob/4d32a10ffe632694aa973c1457f1d3fb9372c737/src/terralib.lua#L1762
    return tpl.entries:map(function(t) return t[2] end)
end



local function istuple(T)
  assert(terralib.types.istype(T))
  if T:isunit() then
    return true
  end
  if not T:isstruct() then
    return false
  end
  if #T.entries == 0 then
    return false
  end
  local ret = true
  for i = 1, #T.entries do
    ret = ret and (T.entries[i] ~= nil)
  end
  return ret
end

local function terralist_to_array(a)
  local b = {}
  for k, v in pairs(a) do
    b[k] = v
  end
  return b
end

local serpent = require("serpent")
local function serialize_pointertofunction(func)
  assert(terralib.types.istype(func) and func:ispointertofunction())
  func = func.type
  local param = terralist_to_array(func.parameters)
  local ret
  if istuple(func.returntype) then
    ret = tuple_type_to_list(func.returntype)
    ret = terralist_to_array(ret)
  else
    ret = {func.returntype}
  end
  local func_array = {["param"] = param, ["ret"] = ret}
  return serpent.dump(func_array)
end

local function type_from_str(type_list, str)
  local T
  if str:match("&") then
    local Tp = type_list[str:sub(2,-1)]
    T = terralib.types.pointer(Tp)
  else
    T = type_list[str]
  end
  return T
end

local function map_str_to_type(type_list, a)
  local b = terralib.newlist(a)
  return b:map(function(t) return type_from_str(type_list, t) end)
end

local function deserialize_pointertofunction(str)
  local ok, obj = serpent.load(str)
  assert(ok)
  local type_list = get_types()
  local param = map_str_to_type(type_list, obj.param)
  local ret = map_str_to_type(type_list, obj.ret)
  return param -> ret
end

local struct foo {}
local function foobar(str)
  local t = terralib.types.newstruct(str)

  return t
end
foobar = terralib.memoize(foobar)

local A = foobar("hello")
local B = foobar("hello")
print(A, B, A == B)
local func = {A, &B, A, double} -> {foo, A, &B}
local ser = serialize_pointertofunction(func)
print(ser)
local de_func = deserialize_pointertofunction(ser)
print(func)
print(de_func)
print(func == de_func)
