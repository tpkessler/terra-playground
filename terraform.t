local process_template, printtable, get_local_vars, get_terra_types, addtoenv

local template = require("template_new")
local concept = require("concept")

local conceptlang = {
	name = "conceptlang";
	entrypoints = {"terraform"};
	keywords = {"where"};
	statement = function(self,lex)
		if lex:matches("terraform") then
			return process_template(self, lex)
		end
	end;
}

local process_where_clause, process_template_parameters, get_template_parameter_list, process_namespace_indexing

--easy set/get access of namespaces of 'n' levels depth
local namespace = {
	__index = function(t, path)
		local n = #path
		local v = t.env
		for k=1,n do
			v = v[path[k]]
		end
		return v
	end,
	__newindex = function(t, path, value)
		local n = #path
		local v = t.env
		for k=1,n-1 do
			v = v[path[k]]
		end
		v[path[n]] = value
	end
}
namespace.new = function(env)
	local t = {env=env}
	return setmetatable(t, namespace)
end

function process_template(self, lex)
	lex:expect("terraform")
	--process methodname and possible indexing
	local path, methodname = process_namespace_indexing(lex)
	--process templatefunction parameters
	local params = process_template_parameters(lex)  
	--process template parameter constraints
	local constraints = process_where_clause(lex)
	--process terra-block
	local terrastmts = lex:terrastats()
	--end of terra-block
	lex:expect("end")
	--give control back to lua
	local luaexprs = lex:luastats()
	--return env-function
	return function(envfun)
		--initialize environment
		local env = envfun()
		local ns = namespace.new(env)
		local alltypes = get_terra_types()
		--get parameter-types list
		local templparams = get_template_parameter_list(env, params, alltypes, constraints)
		--get/register new template function
		local templfun = ns[path] or template.functiontemplate(methodname)
		local argumentlist = terralib.newlist{}
		local localenv = {}
		templfun:adddefinition({[templparams] = function(...)
			local args = terralib.newlist{...}
			assert(#args==#params) --sanity check, concept check is already applied, so this should always be correct.
			local argumentlist = terralib.newlist{}
			for counter,param in ipairs(params) do
				local sym = symbol(args[counter])
				argumentlist:insert(sym)
				localenv[param.name] = sym
			end
			addtoenv(env, localenv)
			return terra([argumentlist])
				[terrastmts(env)]
			end
		end})
		--register template function
		ns[path] = templfun
		--give control back to Lua
		return luaexprs(env)
	end
end

function process_namespace_indexing(lex)
	local ns = terralib.newlist{}
	repeat
		ns:insert(lex:expect(lex.name).value)
	until not lex:nextif(".")
	return ns, ns[#ns] --return path and methodname
end

function get_template_parameter_list(env, params, alltypes, constraints)
	local templparams = terralib.newlist{}
	for _,param in ipairs(params) do
		--treat explicit types
		if terralib.types.istype(alltypes[param.typename]) then
			templparams:insert(alltypes[param.typename])
		--treat as a concept
		else
			local constraint = constraints[param.typename]
			if constraint=="Any" then
				templparams:insert(concept.Any)
			else
				if env[constraint] then
					templparams:insert(env[constraint])
				else
					error("Concept " .. tostring(constraint) .. " not found in current scope.")
				end
			end
		end
	end
	return templparams
end

function process_template_parameters(lex)                                  
	local params = terralib.newlist()         
	if lex:matches("(") then
		lex:expect("(")
		repeat      
			local paramname = lex:expect(lex.name).value
			lex:expect(":")    
			local constraint = lex:expect(lex.name).value      
			params:insert({name=paramname, typename=constraint})                 
		until not lex:nextif(",")                                
		lex:expect(")")                                
	end        
	return params
end

function process_where_clause(lex)                                  
	local params = terralib.newlist()   
	local constraint 
	if lex:matches("where") then
		lex:expect("where")
		lex:expect("{") 
		repeat      
			local param = lex:expect(lex.name).value              
			lex:ref(param)
			if lex:matches("<") then
				lex:expect("<")
				constraint = lex:expect(lex.name).value      
				lex:ref(constraint)
			else
				constraint = "Any"
			end
			params[param] = constraint             
		until not lex:nextif(",")                                
		lex:expect("}")                                
	end        
	return params
end

printtable = function(tab)
	for k,v in pairs(tab) do
		print(k)
		print(v)
		print()
	end 
end

function addtoenv(dest, source)
	for i,v in pairs(source) do
		dest[i] = v
	end
	return dest
end

function get_local_vars()
	--[=[
		Return a key-value list of all lua variables available in the current scope.
	--]=]
	local upvalues = {}
	local thread = 0 -- Index of scope
	local failure = 0 -- It might fail on the inner scope, so break if this larger than 1.
	while true do
		thread = thread + 1
		local index = 0 -- Index of local variables in scope
		while true do
			index = index + 1
			-- The number of scopes is not known before, so we have to iterate
			-- until debug.getlocal throws an error
			local ok, name, value = pcall(debug.getlocal, thread, index)
			if ok and name ~= nil then
				upvalues[name] = value
			else
				if index == 1 then -- no variables in scope
					failure = failure + 1
				end
				break
			end
		end
		if failure > 1 then
			break
		end
	end
	return upvalues
end

function get_terra_types()
	--[=[
		Return key-value list of a terra types available in the current scope.
	--]=]
	local types = {}
	-- First iterate over globally defined types. This includes primitive types
	for k, v in pairs(_G) do
		if terralib.types.istype(v) then
			types[k] = v
			types[tostring(v)] = v
		end
	end
	-- Terra structs or type aliases can be defined with the local keyword,
	-- so we have to iterate over the local lua variables too.
	local upvalues = get_local_vars()
	for k, v in pairs(upvalues) do
		if terralib.types.istype(v) then
			types[k] = v
			types[tostring(v)] = v
		end
	end
	return types
end

return conceptlang