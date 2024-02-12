import "terratest"

local a = 1
local b = 3 

testenv "my test environement" do
  local c = 10
  terradef
    var x = 1
    var y = 2
  end
  test a*b==3
  test a*b==4 --false
  test a+b+c==14
  test a+b+c==15 --false
  test a+b+c==x+y+11
end
