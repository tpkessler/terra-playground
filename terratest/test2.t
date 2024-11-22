-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT


import "terratest"

local a = 1
local b = 2

test a+1==b

terra foo(a : int)
  return a+1
end

test foo(1)==2
test foo(2)==4 --false
