--load 'terralibext' to enable raii
require "terralibext"

local io = terralib.includec("stdio.h")

function AbstractStack(T)

    T.methods.__init = terra(self : &T)
        var x : int64 = 1
        self.data = &x
        self.size = 0
        io.printf("calling base initializer.\n")
    end

    T.methods.set = terra(self : &T, d : int64)
        @self.data = d
    end

    T.methods.get = terra(self : &T)
        return @self.data
    end

    T.methods.size = terra(self : &T)
        return self.size
    end

    T.methods.__dtor = terra(self : &T)
        self.data = nil
        self.size = 0
        io.printf("calling base destructor.\n")
    end

end


struct stack(AbstractStack){
    data : &int64
    size : uint64
}

struct object{
    data : stack
}

terra main()
    var x : object
    x.data:set(2)
    io.printf("my data: %d\n", x.data:get())
    io.printf("my size: %d\n", x.data:size())
end

main()
