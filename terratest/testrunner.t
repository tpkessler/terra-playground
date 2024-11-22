-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

--local prefix = terralib and terralib.terrahome and terralib.terrahome .."/bin/terra" or "../terra"
local prefix = arg[-1]

--is this a testfile?
local function istestfile(filename)
    return string.sub(filename, 1, 4) == "test" and filename~="testrunner.t"
end

--turn list into a set
local function dictionary(list)
    local dict = {}
    for i,v in ipairs(list) do
        dict[v] = true 
    end
    return dict
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
print(string.format("%-15s%-50s%-30s", "Filename", "Test-environment", "Test-result"))
print(format.normal)

--list files to be skipped
local files_to_skip = dictionary{
    "test1.t",
    "test3.t",
    "test5.t",
}

--global - use silent output - only testenv summary
__silent__ = true

--print teststatistics for test environments
for filename in io.popen("ls -p"):lines() do
    if istestfile(filename) and not files_to_skip[filename] then
        local execstring = prefix .. " " .. filename .. " --test --silent"
        local exitcode = os.execute(execstring)
        if exitcode ~= 0 then
            local message = format.bold .. format.red .. "Process exited with exitcode " .. tostring(exitcode)
            io.write(string.format("%-25s%-59s%-30s\n", filename, message, "NA"..format.normal))
        end
    end
end
