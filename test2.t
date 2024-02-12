import "terratest"

local a = 1
local b = 2

test a+1==b

terra foo(a : int)
  return a+1
end

test foo(1)==2
test foo(2)==4
