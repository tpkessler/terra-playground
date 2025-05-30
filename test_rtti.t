local rtti = require("rtti")

import "terratest"

testenv "RTTI" do
    local struct A {
        a: int64
    }
    rtti.base(A)

    local struct B {
        b: double
    }
    rtti.base(B)

    local struct C {
        a: A
        b: B
    }
    rtti.base(C)

    testset "typeid on unmanaged structs" do
        terracode
            var a: A
            var b: B
            var v: &opaque
        end

        test [A.typeid ~= nil]
        test [B.typeid ~= nil]

        test [rtti.dynamic_cast(A)](&a) ~= nil
        test [rtti.dynamic_cast(B)](&a) == nil

        test [rtti.dynamic_cast(A)](&b) == nil
        test [rtti.dynamic_cast(B)](&b) ~= nil
    end

    testset "typeid on managed structs" do
        terracode
            var c: C
        end

        test [C.typeid ~= nil]        
        test [rtti.dynamic_cast(A)](&c) == nil
        test [rtti.dynamic_cast(B)](&c) == nil
        test [rtti.dynamic_cast(C)](&c) ~= nil

        test [rtti.dynamic_cast(A)](&c.a) ~= nil
        test [rtti.dynamic_cast(B)](&c.b) ~= nil
    end
end
