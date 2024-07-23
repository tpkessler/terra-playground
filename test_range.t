import "terratest/terratest"

local io = terralib.includec("stdio.h")
local Alloc = require("alloc")
local rn = require("range")
local Stack = require("example_stack_heap")

local stack = Stack.DynamicStack(int, int)
local DefaultAllocator =  Alloc.DefaultAllocator()
local linrange = rn.Linrange(int)


testenv "linrange" do

    terracode
        var alloc : DefaultAllocator
        var range = linrange{1, 4}
        var s = stack.new(&alloc, 3)
    end

	testset "linrange" do
        terracode
            range:collect(&s)
        end
        test range:size() == 3
        test s:get(0)==1
        test s:get(1)==2
        test s:get(2)==3
	end

    testset "transform" do
        terracode
            var x = 2
            var g = rn.transform([terra(i : int, x : int) return x * i end], x)
            var trange = range >> g
            trange:collect(&s)
        end
        test s:get(0)==2
        test s:get(1)==4
        test s:get(2)==6
    end

end

terra test0()
    io.printf("transform \n")
    var range = linrange{0, 5}
    for i in range do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
test0()

terra test1()
    io.printf("transform \n")
    var range = linrange{0, 5}
    var x = 3
    var g = rn.transform([terra(i : int, x : int) return x * i end], 2)
    var r = range >> g
    for i in r do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
test1()


terra test2()
    io.printf("filter \n")
    var x = 0
    for i in linrange{1, 8} >> rn.filter([terra(i : int, x : int) return i % 2 == x end], x) do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
test2()


local runtests = false

if runtests then

terra test3()
    io.printf("compose transform and filter - lvalues\n")
    var range = linrange{0, 5}
    var x = 0
    var y = 3
    var g = rn.filter([terra(i : int, x : int) return i % 2 == x end], x)
    var h = rn.transform([terra(i : int, y : int) return y * i end], y)
    for i in range >> g >> h do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
test3()

terra test4()
    io.printf("compose transform and filter - rvalues\n")
    var x = 0
    var y = 3
    for i in linrange{0, 5} >> 
                rn.filter([terra(i : int, x : int) return i % 2 == x end], x) >> 
                        rn.transform([terra(i : int, y : int) return y * i end], y) 
    do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
test4()

terra test5()
    io.printf("take\n")
    for i in linrange{0, 10} >> rn.take(4) do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
test5()

terra test6()
    io.printf("drop\n")
    for i in linrange{0, 10} >> rn.drop(4) do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
test6()

terra test7()
    io.printf("take_while\n")
    var x = 5
    for i in linrange{0, 10} >> rn.take_while([terra(i : int, x : int) return i < x end], x) do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
test7()

terra test8()
    io.printf("drop_while\n")
    var x = 6
    for i in linrange{0, 10} >> rn.drop_while([terra(i : int, x : int) return i < x end], x) do
        io.printf("%d\n", i)
    end
    io.printf("\n")
end
test8()

terra test9()
    io.printf("enumerate\n")
    for i,v in rn.enumerate(linrange{4, 10}) do
        io.printf("(%d, %d)\n", i, v)
    end
    io.printf("\n")
end
test9()

terra test10()
    io.printf("join\n")
    for v in rn.join(linrange{1, 4}, linrange{4, 6}, linrange{6, 9}) do
        io.printf("%d\n", v)
    end
    io.printf("\n")
end
test10()

terra test11()
    io.printf("product - 1\n")
    for x in rn.product(linrange{1, 4}) do
        io.printf("(%d)\n", x)
    end
    io.printf("\n")
end
test11()

terra test12()
    io.printf("product - 2\n")
    for x,y in rn.product(linrange{1, 4}, linrange{4, 6}) do
        io.printf("(%d, %d)\n", x, y)
    end
    io.printf("\n")
end
test12()

terra test13()
    io.printf("product - 3\n")
    for x,y,z in rn.product(linrange{1, 4}, linrange{4, 6}, linrange{10, 14}) do
        io.printf("(%d, %d, %d)\n", x, y, z)
    end
    io.printf("\n")
end
test13()

terra test14()
    io.printf("zip - 1\n")
    for x in rn.zip(linrange{1, 4}) do
        io.printf("(%d)\n", x)
    end
    io.printf("\n")
end
test14()

terra test15()
    io.printf("zip - 2\n")
    for x, y in rn.zip(linrange{1, 4}, linrange{2, 6}) do
        io.printf("(%d, %d)\n", x, y)
    end
    io.printf("\n")
end
test15()

terra test16()
    io.printf("zip - 2\n")
    for x, y, z in rn.zip(linrange{1, 4}, linrange{2, 6}, linrange{3, 8}) do
        io.printf("(%d, %d, %d)\n", x, y, z)
    end
    io.printf("\n")
end
test16()


end