-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT


--terratest.t provides a unit testing framework for the terra programming
--language. It's implemented as a terra language extension.
--terratest.t can be used from the terminal as follows:
--"terra terrafile.t --test".
--tests are only run for the "topfile" with the "--test" or "-t" option
--check the tests and README.md for more information on how to use terratest.t

local process_test, process_terrastats, process_testset, process_testenv

local testlang = {
    name = "unittestlang";
    entrypoints = {"testenv","testset","test","terracode"};
    keywords = {"skip"};
    scopelevel = 0;
    env = {scope0 = terralib.newlist(), scope1 = terralib.newlist(), scope2 = terralib.newlist()};
    terrastmts = {notests = terralib.newlist(), scope0 = terralib.newlist(), scope1 = terralib.newlist(), scope2 = terralib.newlist()};
    expression = function(self,lex)
        --`test` can be used in any scoplevel
        if lex:matches("test") then
            return process_test(self, lex)
        end 
        --`testenv` defines scopelevel 1
        if lex:matches("testenv") then
            return process_testenv(self, lex)
        end
        --`testset` defines scopelevel 2
        if lex:matches("testset") then
            return process_testset(self, lex)
        end
        --`terracode` block can be used inside a `testenv` and inside a `testset` 
        if lex:matches("terracode") then
            return process_terrastats(self, lex)
        end
    end;
}

local ffi = require("ffi")

--place to store all testresults
local testsresults = terralib.newlist();
    
--add results to testsresults table
local addToTestResults = terralib.cast({bool, rawstring, int}->{}, 
                            function(testresult, filename, linenumber)
                                testsresults:insert({filename=ffi.string(filename), linenumber=linenumber, passed=testresult})
                            end)

table.clear = function(t)
    local size = #t
    for i = 1, size do
        t[i] = nil
    end
end

local get_parametric_name, process_env_parameters, collect_terra_stmts, addtoenv
local test_finalizer, print_single_passed_test, print_single_failed_test, print_test_stats

--get metatable and check if "--test" or "-t" option is provided as
--an optional argument. 
local mt = getmetatable(_G)
__runalltests__ = false     --global - run all tests
__silent__ = false          --global - silent output (only testenv summary)
local topfile = ""
if mt.__declared["arg"]~=nil then
    for i,v in pairs(arg) do
        if v == "--test" or v == "-t" then
            __runalltests__ = true
        elseif v == "--silent" or v == "-s" then
            __silent__ = true
        end 
    end 
    topfile = arg[0]
end

--define colors for printing test-statistics
format = terralib.newlist()
format.normal = "\27[0m"
format.bold = "\27[1m"
format.red = "\27[31m"
format.green = "\27[32m"

function process_testenv(self, lex)
    --definition of some locally used functions
    local function print_failed_tests(tests)
        for i,test in pairs(tests) do
            if not test.passed then
                print_single_failed_test(test.filename, test.linenumber)
            end
        end
    end
    --open the testenv environment
    lex:expect("testenv")
    -- treat case of parameterized testenv                       
    local skiptestenv, isparametric, params = process_env_parameters(lex)
    --generate testset name and parse code  
    local testenvname = lex:expect(lex.string).value
    lex:expect("do")
    local luaexprs = lex:luastats() -- give control back to lua
    --exit
    local lasttoken = lex:expect("end")
    --exit with nothing if this is not the topfile
    local runtests = __runalltests__ and lasttoken.filename==topfile
    --return env-function
    return function(envfun)
        --return if tests need not be run
        if not runtests or skiptestenv then
 	        return
	    end
        --reinitialize global variables
        self.env = {scope1 = terralib.newlist(), scope2 = terralib.newlist()}
        self.terrastmts = {notests = terralib.newlist(), scope1 = terralib.newlist(), scope2 = terralib.newlist()}
        self.env["scope1"].counter = symbol(int)                  
        self.env["scope1"].passed = symbol(int)                   
        self.env["scope1"].failed = symbol(int)
        table.clear(testsresults)
        --enter scope
        self.scopelevel = 1  -- enter testenv, scopelevel 1
        local env = envfun()
        addtoenv(env, self.env["scope1"]) --everything from scope level 1 should be accessible
        --print parametric name
        local parametricname = get_parametric_name(env, testenvname, params, isparametric)
        if not __silent__ then
            print("\n"..format.bold.."Test Environment: "..format.normal, parametricname)
        end
        --give control back to lua, generating code from 'testset' block, 'terracode' block, and 'test' definition
        local f = function()
            luaexprs(env)
        end
        f() -- evaluate all expressions in a new scope
        -- collect all terra statements and evaluate in a new scope                        
        local terrastmts = collect_terra_stmts(env, self.terrastmts["scope1"])                                                    
        local stats = terrastmts() --extract test statistics
        -- process test statistics
        if __silent__ then
            test_finalizer(parametricname, testsresults)
        else
            print_test_stats("\n  "..format.bold.."inline tests"..format.normal, stats)
            print_failed_tests(testsresults)
        end
        -- exit scope
        self.scopelevel = 0  -- exit testenv, back to scopelevel 0
    end
end

function process_testset(self, lex)
    lex:expect("testset") --open the testset environment
    -- treat case of parameterized testset
    local skiptestset, isparametric, params = process_env_parameters(lex)
    --generate testset name and parse code
    local testsetname = lex:expect(lex.string).value
    lex:expect("do")
    local luaexprs = lex:luastats() --give control back to lua
    lex:expect("end")
    --return env-function
    return function(envfun)
        --return if tests need not be run
        if skiptestset then
 	        return
	    end
        -- check current scope
        if self.scopelevel~=1 then
            error("ParseError: cannot use a `testset` block outside of a `testenv`.") 
        end
        -- enter testset, scopelevel 2
        self.scopelevel = 2
        --add testset test counter
        self.env["scope2"].counter = symbol(int)
        self.env["scope2"].passed = symbol(int)
        self.env["scope2"].failed = symbol(int)    
        --add terra environment variables as symbols
        local env = envfun()
        addtoenv(env, self.env["scope1"]) --everything from scope level 1 should be accessible 
        addtoenv(env, self.env["scope2"]) --everything from scope level 2 should be accessible
        --give control back to lua, generating code from 'terracode' block, and 'test' definition
        local f = function()
            --initialize scope 2 with everything but tests from scope 1
            self.terrastmts["scope2"] = addtoenv(terralib.newlist(), self.terrastmts["notests"])
            luaexprs(env)
        end
        f()
        -- collect all terra statements and evaluate in a new scope
        local terrastmts = collect_terra_stmts(env, self.terrastmts["scope2"])
        local stats = terrastmts() --extract test statistics
        -- process test statistics
        local parametricname = get_parametric_name(env, testsetname, params, isparametric)
        if not __silent__ then
            print_test_stats("\n  "..format.bold.."testset:\t\t"..format.normal..parametricname, stats)
        end
        -- exit current scope
    	self.scopelevel = 1  --exit testset, back to scopelevel 1
    end                       
end

local setenv

function process_terrastats(self, lex)
    lex:expect("terracode")
    local terrastmts = lex:terrastats()
    lex:expect("end")
    --return env-function
    return function(envfun)
    	local env = envfun()
      	local stmts = terrastmts(env)
        if self.scopelevel==1 then
            setenv(self.env["scope1"], stmts)
            self.terrastmts["scope1"]:insert(stmts)
            self.terrastmts["notests"]:insert(stmts) 
        elseif self.scopelevel==2 then
            setenv(self.env["scope2"], stmts)
            self.terrastmts["scope2"]:insert(stmts)
        else
            error("ParseError: cannot use a `terracode` block outside of a `testenv`.") 
        end
    end
end

function process_test(self, lex)
    --definition of locally used functions
    local function evaluate_test_results(passed, file, linenumber)
        if not __silent__ then
            if passed then            
                print_single_passed_test(file, linenumber)
            else                         
                print_single_failed_test(file, linenumber)
            end
        end
    end
    --open test terra statement
    local testtoken = lex:expect("test")
    local testexpr = lex:terraexpr()    --extract the test statement
    local luaexprs = lex:luastats()     --give control back to lua (since `test` has no `end`)
    --return env-function
    return function(envfun)
        local env = envfun()
        --evaluate the terra test-expression and add results to testsresults table
        local process_test_expr = macro(function(ex)
            return quote
                var passed = [ex]
                addToTestResults(passed, [testtoken.filename.."\0"], [testtoken.linenumber])
            in
                passed
            end    
        end)
        local update_test_counter = macro(function(env, passed)
            return quote
                if passed then                    
                    env.passed = env.passed + 1
                else
                    env.failed = env.failed + 1
                end
                env.counter = env.counter + 1
            end
        end)
        --test in scopelevel 0, direct evaluation of tests without support for test statistics
        if self.scopelevel==0 then
            local ex = testexpr(env)
            local passed = terra() : bool
                var passed = [ex]
                addToTestResults(passed, [testtoken.filename], [testtoken.linenumber])
                return passed
            end
            evaluate_test_results(passed(), testtoken.filename, testtoken.linenumber)
        --test in scopelevel 1
        elseif self.scopelevel==1 then
            addtoenv(env, self.env["scope1"]) --add terra environment variables as symbols
            local ex = testexpr(env)    
            self.terrastmts["scope1"]:insert(quote update_test_counter(env, process_test_expr(ex)) end)
        elseif self.scopelevel==2 then
            addtoenv(env, self.env["scope2"]) --add terra environment variables as symbols
            local ex = testexpr(env)
            self.terrastmts["scope2"]:insert(quote update_test_counter(env, process_test_expr(ex)) end)
        end
    	return luaexprs(env)
    end  
end

--get the paramtric name of a 'testset' or 'testenv'
function get_parametric_name(env, envname, params, isparametric)
    local parametricname = envname
    if isparametric then                 
        parametricname = envname.."("..params[1].."="..tostring(env[params[1]])
        for i=2,#params do               
            parametricname = parametricname..","..params[i].."="..tostring(env[params[i]])
        end                              
        parametricname = parametricname..")"
    end
    return parametricname
end

--process the parameters in a parameterized 'testset' or 'testenv'
function process_env_parameters(lex)
    local isparametric = false                                  
    local params = terralib.newlist()
    local skipenv = false         
    if lex:matches("(") then
        lex:expect("(")
        repeat
            if lex:nextif("skip") then
                skipenv = true
            else
                local name = lex:expect(lex.name).value              
                lex:ref(name)                                     
                params:insert(name)
            end                                  
        until not lex:nextif(",")                                
        lex:expect(")")                                          
        isparametric = true                                      
    end        
    return skipenv, isparametric, params
end

--data structure that saves the number of passed and
--failed tests
local struct Stats{
    passed : int
    failed : int
}

--collecting terra statements - used in 'testenv' and 'testset'
function collect_terra_stmts(env, terrastmts)
    local imp = terra()
        var [env.counter] = 0   
        var [env.passed] = 0    
        var [env.failed] = 0
        escape                  
            --the counters are updated here       
            for i=1,#terrastmts do 
                emit quote  [terrastmts[i]] end                 
            end
        end
        return Stats {[env.passed], [env.failed]}
    end
    return imp
end 

--print in __silent__ mode summery of testenv
function test_finalizer(testenvname, tests)
    local passed = 0
    local failed = 0
    local ntotal = 0
    for i,test in pairs(tests) do
        ntotal = ntotal + 1
        if test.passed then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end
    if ntotal > 0 then
        if failed > 0 then
            local filename = tests[1].filename
            local testresult = string.format(format.bold..format.red.."%-6s %s" .. format.normal, tostring(passed) .. "/" .. tostring(ntotal), "tests passed")
            print(string.format("%-25s%-70s%-30s", filename, testenvname, testresult))
        else
            local filename = tests[1].filename
            local testresult = string.format(format.bold..format.green.."%-6s %s" .. format.normal, tostring(passed) .. "/" .. tostring(ntotal), "tests passed")
            print(string.format("%-25s%-70s%-30s", filename, testenvname, testresult))
        end
    end
end

function print_single_passed_test(file, linenumber)
    print("  "..format.bold..format.green.."test passed\n"..format.normal)
end

function print_single_failed_test(file, linenumber)
    print("  "..format.bold..format.red.."test failed in "..file..", linenumber "..linenumber..format.normal) 
end

--printing test statistics - used in 'testenv' and 'testset'
function print_test_stats(name, stats)
    local ntotal = stats.passed + stats.failed  
    print(name)
    if stats.passed>0 then    
        print("  "..format.bold..format.green..stats.passed.."/"..ntotal.." tests passed"..format.normal)
    end
    if stats.failed>0 then                 
        print("  "..format.bold..format.red..stats.failed.."/"..ntotal.." tests failed\n"..format.normal)
    end
end

function setenv(env, stmts)
    for i,s in ipairs(stmts.tree.statements) do
        --variables that are directly initialized
        if s.lhs~=nil then
            for _, v in ipairs(s.lhs) do
                if v.symbol ~= nil then
                    env[v.name] = v.symbol
                else
                    --the other options are
                    if v.select ~= nil then
                        env[v.name] = v.select.symbol
                    end
                end
            end
        end
        --variables that are allocated
        if s.name~=nil and s.symbol~=nil then
            env[s.name] = s.symbol
        end
    end 
end

function addtoenv(dest, source)
    for i,v in pairs(source) do
	    dest[i] = v
    end
    return dest
end

return testlang