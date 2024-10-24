local process_template, printtable

local template = require("template")
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
		if type(path)=="table" then
			local n = #path
			local v = t.env
			for k=1,n do
				v = v[path[k]]
			end
			return v
		else
			return t.env[path]
		end
	end,
	__newindex = function(t, path, value)
		if type(path)=="table" then
			local n = #path
			local v = t.env
			for k=1,n-1 do
				v = v[path[k]]
			end
			v[path[n]] = value
		else
			t.env[path] = value
		end
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
		--add any concept to local environment
		env["Any"] = concept.Any
		--allow easy searching in 'env' of variables that are nested inside tables
		local localenv = namespace.new(env)
		--get parameter-types list
		local templparams = get_template_parameter_list(localenv, params, constraints)
		--get/register new template function
		local templfun = localenv[path] or template.functiontemplate(methodname)
		local argumentlist = terralib.newlist{}
		templfun:adddefinition({[templparams] = terralib.memoize(function(...)
			local args = terralib.newlist{...}
			local argumentlist = terralib.newlist{}
			for counter,param in ipairs(params) do
				local sym = symbol(args[counter])
				argumentlist:insert(sym)
				localenv[param.name] = sym
			end
			return terra([argumentlist])
				[terrastmts(env)]
			end
		end)})
		--register template function
		localenv[path] = templfun
		--give control back to Lua
		return luaexprs(env)
	end
end

function get_template_parameter_list(localenv, params, constraints)
	local templparams = terralib.newlist{}
	for _,param in ipairs(params) do
		local c = constraints[param.typename]
		local typ
		if c then --get concept type
			typ = localenv[c.path] or error("Concept " .. tostring(c.name) .. " not found in current scope.")
		else --get concrete type from 'env' or primitives
			typ = localenv[param.typename] or terralib.types[param.typename] or error("Type " .. tostring(c) .. " not found in current scope.")
		end
		templparams:insert(typ)
	end
	return templparams
end

function process_namespace_indexing(lex)
	local ns = terralib.newlist{}
	repeat
		ns:insert(lex:expect(lex.name).value)
	until not lex:nextif(".")
	return ns, ns[#ns] --return path and methodname
end

function process_template_parameters(lex)                                  
	local params = terralib.newlist()         
	if lex:matches("(") then
		lex:expect("(")
		repeat      
			local paramname = lex:expect(lex.name).value
			lex:expect(":")    
			local paramtype = lex:expect(lex.name).value   
			lex:ref(paramtype) --if paramtype is a concrete type (not a concept), 
			--then make it available in 'env'
			params:insert({name=paramname, typename=paramtype})                 
		until not lex:nextif(",")                                
		lex:expect(")")                                
	end        
	return params
end

function process_where_clause(lex)
	local params = terralib.newlist()   
	local constraint = {}
	if lex:matches("where") then
		lex:expect("where")
		lex:expect("{") 
		repeat      
			local param = lex:expect(lex.name).value
			if lex:matches(":") then
				lex:expect(":")
				constraint.path, constraint.name = process_namespace_indexing(lex)
				lex:ref(constraint.path[1])
			else
				constraint.path = {"Any"}
				constraint.name = "Any"
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

return conceptlang