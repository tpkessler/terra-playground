-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local toml = require("toml")

local prefix = arg[-1]
local config = "config/testrunner.toml"
local path = "."
local help = "Testrunner for unit tests in the terratest unit testing framework\n" ..
             "-----------------------------------------------------------------\n" ..
             "-c/--config TOML file for configuration. Defaults to " .. config .. "\n" ..
             "-p/--path Directory for unit tests. Defaults to the current directory\n" ..
             "-g/--generate Print the default TOML config to stdout and exit" ..
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

--print teststatistics for test environments
config = process_config(config)
for filename in list_tests(config, path) do
    local execstring = prefix .. " " .. filename .. " --test --silent"
    local exitcode = os.execute(execstring)
    if exitcode ~= 0 then
        local message = format.bold .. format.red .. "Process exited with exitcode " .. tostring(exitcode)
        io.write(string.format("%-25s%-59s%-30s\n", filename, message, "NA"..format.normal))
    end
end
