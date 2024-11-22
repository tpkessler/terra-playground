-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT


import "terratest"

local a = 1
local b = 3 

testenv "first test environement" do

local N = 2

for N=1,6 do
testset(N) "my first testset" do

  terracode
    var p = 1
  end

  test N+p==N+1
  test a+b+p+N==N+5
end
end

end
