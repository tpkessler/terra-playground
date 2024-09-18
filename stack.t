-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileContributor: Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concept = require("concept")

local Stack = concept.AbstractInterface:new("Stack", {
  size = {} -> concept.UInteger,
  get = concept.UInteger -> concept.Number,
  set = {concept.UInteger, concept.Number} -> {},
})

return {
    Stack = Stack,
}
