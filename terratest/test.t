import "terratest"

local a = 1
local b = 3 

test a*b==3
test a+b==4


testenv "first test environement" do

local c = 10

terracode
  var x = 1
  var y = 2
end

test x*y==2

local N = 2
testset(N) "my first testset" do

  terracode
    var p = 0
  end

  test N==2
  test a+b+p==4
  test a*b==3
  test a+b+c==14
end

terracode
  var z = 2.0
end

test z==2

testset "my second testset"  do

  terracode
    var t1 = 1
    var t2 = 2
  end

  local k = 10

  test 2*t1+t2+k==4+k
  test t1+t2==3
end

end



testenv "second test environement" do
             
terracode   
  var x = 1   
  var y = 3       
end           
              
test x*y==3

testset "first testset" do
    terracode 
	var z = 4
    end
    test x*y*z==12
end

end
