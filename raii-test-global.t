require "terralibext"
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

a = global(A)

terra main()
    io.printf("a.data = %d\n", a.data)
end
main()