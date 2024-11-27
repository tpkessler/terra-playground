-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT


import "terratest"

testenv "first test environement" do

local z = 10

terracode
  var x = 1
end

testset "my first testset" do
  terracode
    var y = 2
  end
  test x+y+z==13
end

testset "my second testset" do
  terracode
    var p = 5 
  end 
  test x+z+p==16
end     

end
