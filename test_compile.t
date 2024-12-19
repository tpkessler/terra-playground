local compile = require("compile")

import "terratest/terratest"

testenv "Generate header file" do
    local header = compile.getCheader{
        ["awesome_wrapper"] = (
            terra(x: double, y: &opaque, z: rawstring, w: &double): {uint} end
        ),
    }
    local ref = [[
#pragma once
#include <stdint.h>
#include <stdbool.h>
uint32_t awesome_wrapper(double, void *, char *, double *);]]
    test [ref == header]
end

testenv "Generate C API" do
    local terra add(x: int, y: rawstring, z: double): &opaque end
    local name = "testgenerate"
    compile.generateCAPI("testgenerate", {add = add})
    local input = io.open(name .. ".h", "r")
    local header = input:read("*a")
    input:close()
    local refheader = [[
#pragma once
#include <stdint.h>
#include <stdbool.h>
void * add(int32_t, char *, double);]]
    test [header == refheader]
    local obj = io.open(name .. ".o", "rb")
    test [obj ~= nil]
    obj:close()
end
