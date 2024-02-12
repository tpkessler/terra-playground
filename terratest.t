local C = terralib.includec("stdio.h")

local mt = getmetatable(_G)
local runalltests = false
local topfile = ""
if mt.__declared["arg"]~=nil then
    for i,v in pairs(arg) do
        if v=="--test" or v=="-t" then
            runalltests = true
        end 
    end 
    topfile = arg[0]
end
       
format = terralib.newlist()
format.normal = "\27[0m"
format.bold = "\27[1m"
format.red = "\27[31m"
format.green = "\27[32m"

local struct Stats{
    passed : int
    failed : int
}

local function collectTerraStmts(env, terrastmts)
    local q = quote             
        var [env.counter] = 0   
        var [env.passed] = 0    
        var [env.failed] = 0    
    end                         
    for i=1,#terrastmts do 
        q = quote               
            [q]                 
            [terrastmts[i]]
        end                     
    end                         
    q = quote                   
        [q]                     
        return Stats {[env.passed], [env.failed]}
    end      
    return q
end 

local function printTestPassed(file, linenumber)
    print("  "..format.bold..format.green.."test passed\n"..format.normal)
end

local function printTestFailed(file, linenumber)
    print("  "..format.bold..format.red.."test failed in "..file..", linenumber "..linenumber..format.normal) 
end

local function evaluateTestResult(passed, file, linenumber)
    if passed then            
        printTestPassed(file, linenumber)
    else                         
        printTestFailed(file, linenumber)
    end 
end

local function printTestStats(name, stats)
    local ntotal = stats.passed + stats.failed  
    print(name)
    if stats.passed>0 then    
	print("  "..format.bold..format.green..stats.passed.."/"..ntotal.." tests passed"..format.normal)
    end
    if stats.failed>0 then                 
        print("  "..format.bold..format.red..stats.failed.."/"..ntotal.." tests failed\n"..format.normal)
    end
end

local function printFailedTests(tests)
    for i,test in pairs(tests) do
	if not test.passed then
	    printTestFailed(test.filename, test.linenumber)
	end
    end
end

local function ProcessTestenv(self, lex)
    lex:expect("testenv") --open the testenv environment

    -- treat case of parameterized testenv                       
    local isparametric = false                                   
    local params = terralib.newlist()                            
    if lex:matches("(") then                                     
        lex:expect("(")                                          
        repeat      
            local name = lex:expect(lex.name).value              
            lex:ref(name)                                        
            params:insert(name)                                  
        until not lex:nextif(",")                                
        lex:expect(")")                                          
        isparametric = true                                      
    end             
                    
    --generate testset name and parse code  
    local testenvname = lex:expect(lex.string).value
    lex:expect("do")
    local luaexprs = lex:luastats() -- give control back to lua
    
    --exit
    local lasttoken = lex:expect("end")
    --exit with nothing if this is not the topfile
    local runtests = runalltests and lasttoken.filename==topfile

    return function(envfun)
        if not runtests then
 	    return
	end

	--reinitialize global variables
	self.env = {scope1 = terralib.newlist(), scope2 = terralib.newlist()}
	self.terrastmts = {notests = terralib.newlist(), scope1 = terralib.newlist(), scope2 = terralib.newlist()}
 	self.env["scope1"].counter = symbol(int)                  
    	self.env["scope1"].passed = symbol(int)                   
    	self.env["scope1"].failed = symbol(int)
	self.tests = terralib.newlist()

	-- enter scope
	self.scopelevel = 1  -- enter testenv, scopelevel 1
        local env = envfun()
        addtoenv(env, self.env["scope1"]) --everything from scope level 1 should be accessible
	
	-- print parametric name
	local parametricname = testenvname   
        if isparametric then                 
            parametricname = testenvname.."("..params[1].."="..tostring(env[params[1]])
            for i=2,#params do               
                parametricname = parametricname..","..params[i].."="..tostring(env[params[i]])
            end                              
            parametricname = parametricname..")"
        end
	print("\n"..format.bold.."Test Environment: "..format.normal, parametricname)

	local f = function()
	    luaexprs(env)
	end
	f() -- evaluate all expressions in a new scope
	
	-- generate and run terra function                        
        local terrastmts = collectTerraStmts(env, self.terrastmts["scope1"])
	local g = terra()                                         
           [terrastmts]                                           
        end                                                       
        local stats = g() --extract test statistics

        -- process test statistics
        printTestStats("\n  "..format.bold.."inline tests"..format.normal, stats)
	printFailedTests(self.tests)
	
	-- exit scope
	self.scopelevel = 0  -- exit testenv, back to scopelevel 0
        self.tests = terralib.newlist()
    end
end

local function ProcessTestset(self, lex)
    lex:expect("testset") --open the testset environment
    
    -- treat case of parameterized testset
    local isparametric = false
    local params = terralib.newlist()
    if lex:matches("(") then
	lex:expect("(")
	repeat
	    local name = lex:expect(lex.name).value
	    lex:ref(name)
	    params:insert(name)
	until not lex:nextif(",")
	lex:expect(")")
	isparametric = true
    end

    --generate testset name and parse code
    local testsetname = lex:expect(lex.string).value
    lex:expect("do")
    local luaexprs = lex:luastats() --give control back to lua
    lex:expect("end")
    return function(envfun)
	-- enter new scope
	self.scopelevel = 2  -- enter testset, scopelevel 2
	
	--add terra environment variables as symbols
    	self.env["scope2"].counter = symbol(int)
    	self.env["scope2"].passed = symbol(int)
    	self.env["scope2"].failed = symbol(int)    
    	local env = envfun()
	addtoenv(env, self.env["scope1"]) --everything from scope level 1 should be accessible 
	addtoenv(env, self.env["scope2"]) --everything from scope level 2 should be accessible
	
	-- evaluate all expressions in a new scope
	local f = function()
	    --initialize scope 2 with everything but tests from scope 1
	    self.terrastmts["scope2"] = addtoenv(terralib.newlist(), self.terrastmts["notests"])
	    luaexprs(env)
	end
	f()

	-- generate and run terra function
	local terrastmts = collectTerraStmts(env, self.terrastmts["scope2"])
	local g = terra()
	   [terrastmts]
	end
	local stats = g() --extract test statistics

	-- process test statistics
	local parametricname = testsetname
	if isparametric then
	    parametricname = testsetname.."("..params[1].."="..tostring(env[params[1]])
	    for i=2,#params do
		parametricname = parametricname..","..params[i].."="..tostring(env[params[i]])
	    end
	    parametricname = parametricname..")"
	end
	printTestStats("\n  "..format.bold.."testset:\t\t"..format.normal..parametricname, stats)

	-- exit current scope
    	self.scopelevel = 1  --exit testset, back to scopelevel 1
    end                       
end

local function ProcessTerrastats(self, lex)
    lex:expect("terradef")
    local terrastmts = lex:terrastats()
    lex:expect("end")
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
	end
    end 
end

local function ProcessTest(self, lex)
    local testtoken = lex:expect("test")
    local testexpr = lex:terraexpr() --extract the test statement
    local luaexprs = lex:luastats() --give control back to lua (since `test` has no `end`)
    return function(envfun)
	local env = envfun()
 	local ex
	local addToTestResults = terralib.cast({bool}->{}, function(testresult)
	    self.tests:insert({filename=testtoken.filename, linenumber=testtoken.linenumber, passed=testresult})
	end)
	--test in scopelevel 0, direct evaluation of tests without support for test statistics
	if self.scopelevel==0 then
	    ex = testexpr(env)
	    local passed = terra() : bool
		var passed = [ex]
		addToTestResults(passed)
                return passed
            end    
	    evaluateTestResult(passed(), testtoken.filename, testtoken.linenumber)
	--test in scopelevel 1
	elseif self.scopelevel==1 then
	    addtoenv(env, self.env["scope1"]) --add terra environment variables as symbols
	    ex = testexpr(env)	    
	    self.terrastmts["scope1"]:insert(quote
		var passed = [ex]
	        if passed then                    
                    env.passed = env.passed + 1
                else
                    env.failed = env.failed + 1
                end
                env.counter = env.counter + 1
	        addToTestResults(passed)
	    end)
	elseif self.scopelevel==2 then
	    addtoenv(env, self.env["scope2"]) --add terra environment variables as symbols
	    ex = testexpr(env)
	    self.terrastmts["scope2"]:insert(quote
	        var passed = [ex]
	        if passed==true then
		    env.passed = env.passed + 1
	        else
		    env.failed = env.failed + 1
	        end
	        env.counter = env.counter + 1
		addToTestResults(passed)
	    end)
	end
    	return luaexprs(env)
    end  
end

local testlang = {
    name = "unittestlang";
    entrypoints = {"testenv","testset","test","terradef"};
    keywords = {};
    scopelevel = 0;
    tests = terralib.newlist();
    env = {scope0 = terralib.newlist(), scope1 = terralib.newlist(), scope2 = terralib.newlist()};
    terrastmts = {notests = terralib.newlist(), scope0 = terralib.newlist(), scope1 = terralib.newlist(), scope2 = terralib.newlist()};
    expression = function(self,lex)
	if lex:matches("testenv") then
	    return ProcessTestenv(self, lex)
	end
	if lex:matches("testset") then
	    return ProcessTestset(self, lex)
        end
	if lex:matches("terradef") then
	    return ProcessTerrastats(self, lex)
	end
	if lex:matches("test") then
	    return ProcessTest(self, lex)
	end
    end;
}

function setenv(env, stmts)
    for i,s in pairs(stmts.tree.statements) do
	if s.lhs~=nil then
            local name = s.lhs[1].name
            local sym = s.lhs[1].symbol
            env[name] = sym 
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
