-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local toml = require("toml")
local alloc = require("alloc")
local lambda = require("lambda")
local thread = require("thread")
local C = terralib.includecstring[[
#include <stdio.h>
#include <stdlib.h>
]]

local prefix = arg[-1]
local config = "config/testrunner.toml"
local path = "."
local help = "Testrunner for unit tests in the terratest unit testing framework\n" ..
             "-----------------------------------------------------------------\n" ..
             "-c/--config TOML file for configuration. Defaults to " .. config .. "\n" ..
             "-p/--path Directory for unit tests. Defaults to the current directory\n" ..
             "-g/--generate Print the default TOML config to stdout and exit\n" ..
             "-h/--help Print this help message and exit"
local DEFAULT_REGEX = "^test_(.+).t$"

local function print_default_config()
    print("[test]")
    print("regex = " .. "\"" .. DEFAULT_REGEX .. "\"")
    print("ignored = []")
end
for i, a in ipairs(arg) do
    if a == "-c" or a == "--config" then
        config = arg[i + 1]
    elseif a == "-p" or a == "--path" then
        path = arg[i + 1]
    elseif a == "-g" or a == "--generate" then
        print_default_config()
        os.exit(0)
    elseif a == "-h" or a == "--help" then
        print(help)
        os.exit(0)
    end
end



local function process_config(config)
    local input = io.open(config)
    local content = input and input:read("*a") or ""
    if input then
        input:close()
    end
    local content = toml.parse(content)
    content.test = content.test or {}
    local ignored = {}
    for _, file in pairs(content.test.ignored or {}) do
        ignored[file] = true
    end
    return {
        test = {
            regex = content.test.regex or DEFAULT_REGEX,
            ignored = ignored,
        },
    }
end

local function list_tests(config, path)
    return coroutine.wrap(
        function()
            local dir = io.popen("ls -p " .. path)
            for filename in dir:lines() do
                if (
                    filename:find(config.test.regex)
                    and not config.test.ignored[filename]
                    ) then
                    coroutine.yield(filename)
                end
            end
            dir:close()
        end
    )
end

--define colors for printing test-statistics
format = terralib.newlist()
format.normal = "\27[0m"
format.bold = "\27[1m"
format.red = "\27[31m"
format.green = "\27[32m"
format.yellow = "\27[33m"
format.header = format.bold..format.yellow

--print the header
print(format.header)
print(string.format("%-25s%-70s%-30s", "Filename", "Test-environment", "Test-result"))
print(format.normal)

--global - use silent output - only testenv summary
__silent__ = true


config = process_config(config)

local gmutex = global(thread.mutex)
gmutex:get():__init()
terra main()
    var alloc: alloc.DefaultAllocator()
    var tp = thread.threadpool.new(&alloc, thread.max_threads())
    escape
        for filename in list_tests(config, path) do
            local execstring = prefix .. " " .. filename .. " --test --silent"
            emit quote
                tp:submit(
                    &alloc,
                    lambda.new(
                        [
                            terra(i: int, cmd: rawstring)
                                var stream = C.popen(cmd, "r")
                                do
                                    -- var grd: thread.lock_guard = gmutex
                                    while true do
                                        var c = C.fgetc(stream)
                                        if c < 0 then
                                            break
                                        end
                                        C.putchar(c)
                                    end
                                end
                                var res = C.pclose(stream)
                                if res ~= 0 then
                                    escape
                                    local message = (
                                        format.bold ..
                                        format.red ..
                                        "Process exited with exitcode "
                                    )
                                    emit quote
                                            do
                                                -- var grd: thread.lock_guard = (
                                                --     gmutex
                                                -- )
                                                C.printf(
                                                    "%-25s%-59s%d%-30s\n",
                                                    [filename],
                                                    [message],
                                                    res,
                                                    ["NA" .. format.normal]
                                                )
                                            end
                                        end
                                    end
                                end
                            end
                        ],
                        {cmd = [execstring]}
                    ),
                    1
                )
            end
        end
    end
    return 0
end
main()

gmutex:get():__dtor()
