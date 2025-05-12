-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local json = require("json")

import "terratest/terratest"

testenv "JSON" do
    testset "New" do
        terracode
            var root = json.json_object.new()
        end
        test true -- We only test if the code doesn't crash.
    end

    testset "Set double" do
        local C = terralib.includec("string.h")
        terracode
            var root = json.json_object.new()
            root:set("val", 1.2)
            var ref = [
[[
{
  "val":1.2
}]]
            ]
            var res = root:tostring()
        end
        test C.strcmp(ref, res) == 0
    end

    testset "Get double" do
        terracode
            var root = json.json_object.new()
            var key = "val"
            var ref = 1.2
            root:set(key, ref)
            var res: double = root:get(key)
        end
        test ref == res
    end

    testset "Set and get string" do
        local C = terralib.includec("string.h")
        terracode
            var root = json.json_object.new()
            var key = "name"
            var ref = "terra"
            root:set(key, ref)
            var res: rawstring = root:get(key)
        end
        test C.strcmp(ref, res) == 0
    end

    testset "Nested JSON" do
        local C = terralib.includec("stdio.h")
        terracode
            var root = json.json_object.new()
            var lang = json.json_object.new()
            lang:set("terra", 9.)
            lang:set("C", 10.)
            root:set("scores", lang)
            var ref = root:get("scores")
            var terra_score: double = ref:get("terra")
            var C_score: double = ref:get("C")
        end
        test terra_score == 9.
        test C_score == 10.
    end
end
