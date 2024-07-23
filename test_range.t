import "terratest/terratest"

local io = terralib.includec("stdio.h")
local Alloc = require("alloc")
local rn = require("range")
local Stack = require("example_stack_heap")

local stack = Stack.DynamicStack(int, int)
local DefaultAllocator =  Alloc.DefaultAllocator()
local linrange = rn.Linrange(int)


testenv "lambda's" do

    testset "no captures" do
        terracode
            var p = rn.lambda([terra(i : int) return i * i end]) 
        end
        test p(1) == 1
        test p(2) == 4
	end

    testset "with captured vars" do
        terracode
            var x, y = 2, 3
            var p = rn.lambda([terra(i : int, x : int, y : int) return i * i * x * y end], x, y) 
        end
        test p(1) == 6
        test p(2) == 24
	end

end

testenv "range adapters" do

    terracode
        var alloc : DefaultAllocator
        var s = stack.new(&alloc, 10)
    end

	testset "linrange" do
        terracode
            var range = linrange{1, 4}
            range:collect(&s)
        end
        test s:size() == 3
        test s:get(0)==1
        test s:get(1)==2
        test s:get(2)==3
	end

    testset "transform" do
        terracode
            var x = 2
            var g = rn.transform([terra(i : int, x : int) return x * i end], x)
            var range = linrange{1, 4} >> g
            range:collect(&s)
        end
        test s:size()==3
        test s:get(0)==2
        test s:get(1)==4
        test s:get(2)==6
    end

    testset "filter" do
        terracode
            var x = 1
            var range = linrange{1, 7} >> rn.filter([terra(i : int, x : int) return i % 2 == x end], x)
            range:collect(&s)
        end
        test s:size()==3
        test s:get(0)==1
        test s:get(1)==3
        test s:get(2)==5
    end

    testset "take" do
        terracode
            var range = linrange{1, 10} >> rn.take(3)
            range:collect(&s)
        end
        test s:size()==3
        test s:get(0)==1
        test s:get(1)==2
        test s:get(2)==3
    end

    testset "drop" do
        terracode
            var range = linrange{1, 10} >> rn.drop(6)
            range:collect(&s)
        end
        test s:size()==3
        test s:get(0)==7
        test s:get(1)==8
        test s:get(2)==9
    end

    testset "take_while" do
        terracode
            var range = linrange{1, 10} >> rn.take_while([terra(i : int) return i < 4 end])
            range:collect(&s)
        end
        test s:size()==3
        test s:get(0)==1
        test s:get(1)==2
        test s:get(2)==3
    end

    testset "drop_while" do
        terracode
            var x = 5
            var range = linrange{1, 10} >> rn.drop_while([terra(i : int) return i < 7 end])
            range:collect(&s)
        end
        test s:size()==3
        test s:get(0)==7
        test s:get(1)==8
        test s:get(2)==9
    end


end

testenv "range composition" do

    terracode
        var alloc : DefaultAllocator
        var s = stack.new(&alloc, 10)
    end

    testset "compose transform and filter - lvalues" do
        terracode
            var r = linrange{0, 5}
            var x = 0
            var y = 3
            var g = rn.filter([terra(i : int, x : int) return i % 2 == x end], x)
            var h = rn.transform([terra(i : int, y : int) return y * i end], y)
            var range = r >> g >> h
            range:collect(&s)
        end
        test s:size()==3
        test s:get(0)==0
        test s:get(1)==6
        test s:get(2)==12
    end

    testset "compose transform and filter - rvalues" do
        terracode
            var x = 0
            var y = 3
            for v in linrange{0, 5} >> 
                        rn.filter([terra(i : int, x : int) return i % 2 == x end], x) >>
                            rn.transform([terra(i : int, y : int) return y * i end], y) do
                s:push(v)
            end
        end
        test s:size()==3
        test s:get(0)==0
        test s:get(1)==6
        test s:get(2)==12
    end

end

testenv "range combiners" do

    terracode
        var alloc : DefaultAllocator
        var j = stack.new(&alloc, 10)
        var s = stack.new(&alloc, 10)
    end

    testset "join" do
        terracode
            var range = rn.join(linrange{1, 3}, linrange{3, 5}, linrange{5, 7})
            for v in range do
                s:push(v)
            end
        end
        test s:size()==6
        for i = 1, 6 do
            test s:get([i-1]) == i
        end
    end

    testset "enumerate" do
        terracode
            for i,v in rn.enumerate(linrange{1, 4}) do
                j:push(i)
                s:push(v)
            end
        end
        test j:size()==3 and s:size()==3
        test j:get(0)==0 and s:get(0)==1
        test j:get(1)==1 and s:get(1)==2
        test j:get(2)==2 and s:get(2)==3
    end

    testset "zip - 1" do
        terracode
            var U = stack.new(&alloc, 10)
            for u in rn.zip(linrange{1, 4}) do
                U:push(u)
            end
        end
        test U:size()==3
        test U:get(0)==1
        test U:get(1)==2
        test U:get(2)==3
    end

    testset "zip - 2" do
        terracode
            var U = stack.new(&alloc, 10)
            var V = stack.new(&alloc, 10)
            for u,v in rn.zip(linrange{1, 4}, linrange{2, 6}) do
                U:push(u)
                V:push(v)
            end
        end
        test U:size()==3 and V:size()==3
        test U:get(0)==1 and V:get(0)==2
        test U:get(1)==2 and V:get(1)==3
        test U:get(2)==3 and V:get(2)==4
    end

    testset "zip - 3" do
        terracode
            var U = stack.new(&alloc, 10)
            var V = stack.new(&alloc, 10)
            var W = stack.new(&alloc, 10)
            for u,v,w in rn.zip(linrange{1, 4}, linrange{2, 6}, linrange{3, 7}) do
                U:push(u)
                V:push(v)
                W:push(w)
            end
        end
        test U:size()==3 and V:size()==3 and W:size()==3
        test U:get(0)==1 and V:get(0)==2 and W:get(0)==3
        test U:get(1)==2 and V:get(1)==3 and W:get(1)==4
        test U:get(2)==3 and V:get(2)==4 and W:get(2)==5
    end

    testset "product - 1" do
        terracode
            var U = stack.new(&alloc, 10)
            for u in rn.product(linrange{1, 4}) do
                U:push(u)
            end
        end
        test U:size()==3
        test U:get(0)==1
        test U:get(1)==2
        test U:get(2)==3
    end

    testset "product - 2" do
        terracode
            var U = stack.new(&alloc, 10)
            var V = stack.new(&alloc, 10)
            for u,v in rn.product(linrange{1, 4}, linrange{2, 4}) do
                U:push(u)
                V:push(v)
            end
        end
        test U:size()==6 and V:size()==6
        test U:get(0)==1 and V:get(0)==2
        test U:get(1)==2 and V:get(1)==2
        test U:get(2)==3 and V:get(2)==2
        test U:get(3)==1 and V:get(3)==3
        test U:get(4)==2 and V:get(4)==3
        test U:get(5)==3 and V:get(5)==3
    end

    testset "product - 3" do
        terracode
            var U = stack.new(&alloc, 16)
            var V = stack.new(&alloc, 16)
            var W = stack.new(&alloc, 16)
            for u,v,w in rn.product(linrange{1, 4}, linrange{2, 4}, linrange{3, 5}) do
                U:push(u)
                V:push(v)
                W:push(w)
            end
        end
        test U:size()==12
        test U:get(0)==1 and V:get(0)==2 and W:get(0)==3
        test U:get(11)==3 and V:get(11)==3 and W:get(11)==4
    end

end