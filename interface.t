--[[
Enforce implementation of methods for static interfaces.
--]]
-- SPDX-License-Identifier: MIT
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>

local function has_key(tab, key)
--[[
Checks if a table contains a given key.

Arguments:
    tab: a table
    key: a key, can be a string or an integer

Returns:
    True if tab contains an entry with given key, false otherwise
 --]]
  for k, v in pairs(tab) do
    if k == key then
      return true
    end
  end
  return false
end

local function assert_equal_signature(actual, desired)
--[[
Compares two terra function signatures and checks if they are equal,
i.e. if they have the same number of arguments with identical types
and same return value(s).

Arguments:
    actual: The function signature to be checked
    desired: The reference function signature

Returns:
   Throws an error if the signatures don't match. If they match, the function
   is silent.
--]]
  local desired_sig = desired.type.parameters
  local actual_sig = actual.type.parameters

  assert(#desired_sig == #actual_sig,
	  "Number of function parameters don't match: " ..
	  string.format("Desired signature has %d parameters but %d were given",
	  	#desired_sig, #actual_sig))

  for k, v in pairs(desired_sig) do
	  assert(actual_sig[k] == desired_sig[k],
	  	"Actual signature doesn't match desired signature\n" ..
		string.format("At position %s the desired value is %s but %s was given.",
			k, tostring(v), tostring(actual_sig[k])))
  end

  -- Return type is a complicated table that includes function pointers.
  -- However, tostring() returns a unique identifier to check if the
  -- return values agree.
  local desired_ret = desired.type.returntype
  local actual_ret = actual.type.returntype
  assert(tostring(desired_ret) == tostring(actual_ret),
  	"Actual return type " .. tostring(actual_ret) ..
	" doesn't match the desired " .. tostring(desired_ret))
end

local S = {}

function S.assert_implemented(T, must_implement)
--[[
Check if all given methods are implemented for a given type

For a terra type T this methods iterates over the must_implement
and checks if: first, a method with the given name as a key
in the table exists and second, if the given signature matches
the implementation.

Arguments:
    T: Terra type that should provide certain methods
    must_implement: Table with keys equal the method names
                    and values as terra function signatures.

Returns:
    Throws and error if one the methods is not correctly implemented.
    Either because if doesn't exist or that the signature doesn't match
    the reference.
--]]
  local methods = T.methods
  for func, sig in pairs(must_implement) do
    assert(has_key(methods, func),
      "Missing implementation of " .. func .. " for type " .. tostring(T))
	assert_equal_signature(sig, methods[func])
  end
end

return S
