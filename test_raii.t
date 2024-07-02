require "terralibext"           --load 'terralibext' to enable raii

import "terratest/terratest"

io = terralib.includec("stdio.h")

struct A{
    data : int
}

A.methods.__init = terra(self : &A)
    io.printf("__init: calling initializer.\n")
    self.data = 1
end

A.methods.__dtor = terra(self : &A)
    io.printf("__dtor: calling destructor.\n")
    self.data = -1
end

A.methods.__copy = terralib.overloadedfunction("__copy")
A.methods.__copy:adddefinition(terra(from : &A, to : &A)
    io.printf("__copy: calling copy assignment {&A, &A} -> {}.\n")
    to.data = from.data + 10
end)
A.methods.__copy:adddefinition(terra(from : int, to : &A)
    io.printf("__copy: calling copy assignment {int, &A} -> {}.\n")
    to.data = from
end)
A.methods.__copy:adddefinition(terra(from : &A, to : &int)
    io.printf("__copy: calling copy assignment {&A, &int} -> {}.\n")
    @to = from.data
end)


testenv "RAII" do

    testset "testing __init metamethod" do
        terracode
            var a : A
        end
        test a.data == 1
    end

    testset "testing __dtor metamethod" do
        terracode
            var x : &int
            do
                var a : A
                x = &a.data
            end
        end
        test @x == -1
    end

    testset "testing __copy metamethod in copy-construction" do
        terracode
            var a : A
            var b = a
        end
        test b.data == 11
    end

    testset "testing __copy metamethod in copy-assignment" do
        terracode
            var a : A
            a.data = 2
            var b : A
            b = a
        end
        test b.data == 12
    end

    testset "testing __copy metamethod in copy-assignment from integer to struct" do
        terracode
            var a : A
            a = 3
        end
        test a.data == 3
    end

    testset "testing __copy metamethod in copy-assignment from struct to integer" do
        terracode
            var a : A
            var x : int
            a.data = 5
            x = a
        end
        test x == 5
    end

end
