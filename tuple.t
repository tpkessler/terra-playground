-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

-- Helper functions for tuples

local function ntuple(T, N)
    local types = terralib.newlist()
    for k=1, N do
        types:insert(T)
    end
    return tuple(unpack(types))
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

local function dimensiontuple(T)
    local dim = {}
    local function go(S, dimS)
        if istuple(S) then
            for i, e in pairs(unpacktuple(S)) do
                dimS[i] = {}
                go(e, dimS[i])
            end
        end
    end
    local dim = {}
    go(T, dim)
    return dim
end

local function tensortuple(T)
    local dim = dimensiontuple(T)

    local loc = dim
    local ref = {}
    while #loc > 0 do
        ref[#ref + 1] = #loc
        loc = loc[1]
    end

    local function go(dim, lvl)
        assert((#dim == 0 and ref[lvl] == nil) or #dim == ref[lvl],
            string.format("Dimension %d expected but got %d", ref[lvl] or 0, #dim))
        for i = 1, #dim do
            go(dim[i], lvl + 1)
        end
    end

    go(dim, 1)
    return ref
end

return {
    ntuple = ntuple,
    istuple = istuple,
    unpacktuple = unpacktuple,
    dimensiontuple = dimensiontuple,
    tensortuple = tensortuple,
}
