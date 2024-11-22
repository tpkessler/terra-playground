-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT


import "terratest"

terra set(x: &int)
  @x = 1
end

n = 1

testenv(skip) "testenv 1" do

  terracode
    var x: int[n]
    set(x)
    var y = x[0]
  end
  test x[0] == 1
  test y == 1

end

testenv "testenv 2" do

    testset "testset 1" do
        terracode
            var x: int[n]
            set(x)
            var y = x[0]
        end
        test x[0] == 1
        test y == 1
    end

    testset(skip) "testset 2" do
        terracode
            var x: int[n]
            set(x)
            var y = x[0]
        end
        test x[0] == 1
        test y == 1
    end
end
