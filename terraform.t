-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local base = require("base")
local template = require("template")
local concept = require("concept")

local generate_terrafun, parse_terraform_statement, process_free_function_statement, process_class_method_statement
local namespace, process_method_name, process_where_clause, process_template_parameters, get_template_parameter_list, process_namespace_indexing
local isclasstemplate, isnamespacedfunctiontemplate, isfreefunctiontemplate, isstaticmethod, isvarargstemplate

local printtable = function(tab)
	for k,v in pairs(tab) do
		print(k)
		print(v)
		print()
	end
end

local conceptlang = {
	name = "conceptlang";
	entrypoints = {"terraform"};
	keywords = {"where"};
	statement = 
		function(self,lex)
			local templ = parse_terraform_statement(self,lex)
			if isclasstemplate(templ) then
				return process_class_method_statement(templ)
			else
				if isnamespacedfunctiontemplate(templ) then
					return process_namespaced_function_statement(templ)
				elseif isfreefunctiontemplate(templ) then
					return process_free_function_statement(templ), { templ.path } -- create the statement: path = ctor(envfun)
				end
			end
		end;
	localstatement = 
		function(self,lex)
			local templ = parse_terraform_statement(self,lex)
			if isfreefunctiontemplate(templ) then
				return process_free_function_statement(templ), { templ.path } -- create the statement: path = ctor(envfun)
			end
		end;
}

function table.shallow_copy(t)
  	local t2 = {}
  	for k,v in pairs(t) do
    	t2[k] = v
	end
	return t2
end

function parse_terraform_statement(self,lex)
	local templ = {}
	lex:expect("terraform")
	--process method path / class path
	templ.path = process_namespace_indexing(lex)
	templ.classname, templ.methodname = process_method_name(lex, templ.path)
	--process templatefunction parameters
	templ.params = process_template_parameters(lex, templ.classname)
	--process template parameter constraints
	templ.constraints = process_where_clause(lex)
	--process terra-block
	templ.terrastmts = lex:terrastats()
	--end of terra-block
	lex:expect("end")
	return templ
end

function generate_terrafun(templ, localenv)
	return function(...)
		local types = terralib.newlist{...}
		local argumentlist = terralib.newlist{}
		for counter,param in ipairs(templ.params) do
			local argtype
			if param.typename=="__varargs__" then
				local varargs = terralib.newlist{}
				for k=counter,#types do
					varargs:insert(types[k])
				end
				argtype = tuple(unpack(varargs))
			else
				argtype = types[counter]
			end
			local sym = symbol(argtype)
			argumentlist:insert(sym)
			--add variable and its type to the local environment
			localenv[param.name] = sym
		end
		return terra([argumentlist])
			[templ.terrastmts(localenv)]
		end
	end
end

function process_free_function_statement(templ)
	return function(envfun)
		--initialize environment and allow easy searching in 'env' 
		--of variables that are nested inside tables
		local localenv = namespace.new(envfun())
		--get parameter-types list
		local paramconceptlist = get_template_parameter_list(localenv, templ.params, templ.constraints)
		--get/register new template function
		local templfun = localenv[templ.path] or template.functiontemplate(templ.methodname)
		--add current template method implementation
		templfun:adddefinition({[paramconceptlist] = terralib.memoize(generate_terrafun(templ,localenv))})
		return templfun
	end
end

function process_namespaced_function_statement(templ)
	return function(envfun)
		--initialize environment and allow easy searching in 'env' 
		--of variables that are nested inside tables
		local localenv = namespace.new(envfun())
		--get parameter-types list
		local paramconceptlist = get_template_parameter_list(localenv, templ.params, templ.constraints)
		--get/register new template function
		local templfun
		if isstaticmethod(templ,localenv) then
			--case of a static method
			local class = localenv(templ.path,1)
			if not class["staticmethods"] then base.AbstractBase(class) end --add base functionality
			templfun = class["staticmethods"][templ.methodname] or template.functiontemplate(templ.methodname)
		else
			templfun = localenv[templ.path] or template.functiontemplate(templ.methodname)
		end
		--add current template method implementation
		templfun:adddefinition({[paramconceptlist] = terralib.memoize(generate_terrafun(templ,localenv))})
		--register method
		if isstaticmethod(templ,localenv) then
			local class = localenv(templ.path,1)
			class["staticmethods"][templ.methodname] = templfun
		else
			localenv[templ.path] = templfun
		end
	end
end

function process_class_method_statement(templ)
	return function(envfun)
		--initialize environment and allow easy searching in 'env' 
		--of variables that are nested inside tables
		local localenv = namespace.new(envfun())
		--get parameter-types list
		local paramconceptlist = get_template_parameter_list(localenv, templ.params, templ.constraints)
		--get/register new template function
		local class = localenv[templ.path]
		if not class["templates"] then base.AbstractBase(class) end --add base functionality
		local templfun = class["templates"][templ.methodname] or template.Template:new(templ.methodname)
		--add current template method implementation
		templfun:adddefinition({[paramconceptlist] = terralib.memoize(generate_terrafun(templ,localenv))})
		--register class method
		class["templates"][templ.methodname] = templfun
	end
end

--easy set/get access of namespaces of 'n' levels depth
namespace = {
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
	end,
	__call = function(t, path, i)
		local i = i or 0
		if type(path)=="table" then
			local n = #path-i
			local v = t.env
			for k=1,n do
				v = v[path[k]]
			end
			return v
		else
			return t.env[path]
		end
	end,
}
namespace.new = function(env)
	env["Any"] = concept.Any
	env["Vararg"] = concept.Vararg
	local t = {env=env}
	return setmetatable(t, namespace)
end

local function dereference(v)
	if v:ispointer() then
		return dereference(v.type)
	end
	return v
end

function get_template_parameter_list(localenv, params, constraints)
	local uniqueparams, pos, ref = terralib.newlist(), terralib.newlist(), terralib.newlist()
	local counter = 1
	local ctrs = table.shallow_copy(constraints)
	for i,param in ipairs(params) do
		local c = ctrs[param.typename]
		local tp
		if c then --c is either a concept or has been mutated to an integer that points to
		--a concept already treated in uniqueparams
			if type(c)=="number" then
				--already treated in uniqueparams, so insert number 'c' and do not
				--change uniqueparams
				pos:insert(c)
				ref:insert(param.nref)
			else
				--get concept type
				tp = localenv[c.path] or error("Concept " .. tostring(c.name) .. " not found in current scope.")
				ctrs[param.typename] = counter --update to a number in uniqueparams
				--update tables defining template parameter list
				uniqueparams:insert(tp)
				pos:insert(counter)
				ref:insert(param.nref)
				counter = counter + 1
			end
		else 
			--get concrete type from 'env' or primitives
			tp = localenv[param.typename] or terralib.types[param.typename] or error("Could not find " .. param.typename)
			--update tables defining template parameter list
			uniqueparams:insert(tp)
			pos:insert(counter)
			ref:insert(param.nref)
			counter = counter + 1
		end
	end
	return template.paramlist.new(uniqueparams, pos, ref)
end

function process_method_name(lex, path)
	local classname, methodname
	if lex:nextif(":") then
		classname = path[#path]
		methodname = lex:expect(lex.name).value
	else
		methodname = path[#path]
	end
	return classname, methodname
end

function process_namespace_indexing(lex)
	local path = terralib.newlist{}
	repeat
		path:insert(lex:expect(lex.name).value)
	until not lex:nextif(".")
	lex:ref(path[1]) --add root entry to local environment
	return path, path[#path]
end

function process_template_parameters(lex,classname)
	local params = terralib.newlist()
	if classname then
		--add first parameter 'self'
		params:insert({name="self", typename=classname, nref=1})
	end
	if lex:nextif("(") then
		repeat      
			local paramname = lex:expect(lex.name).value
			if lex:nextif(":") then
				--is this a reference to a type?
				local nref = 0
				while lex:nextif("&") do
					nref = nref + 1
				end
				local paramtype = lex:expect(lex.name).value
				lex:ref(paramtype) --if paramtype is a concrete type (not a concept), 
				--then make it available in 'env'
				params:insert({name=paramname, typename=paramtype, nref=nref}) 
			elseif lex:nextif("...") then --expecting ...
				params:insert({name=paramname, typename="__varargs__", nref=0})
				break --... is the last argument in the loop
			else
				params:insert({name=paramname, typename="__ducktype__", nref=0})
			end   
		until not lex:nextif(",")
		lex:expect(")")
	end
	return params
end

local function process_single_constraint(lex)
	if lex:nextif(":") then
		local path, name = process_namespace_indexing(lex)
		lex:ref(path[1])
		return {path=path, name=name}
	else
		return {path = {"Any"}, name = "Any"}
	end
end

function process_where_clause(lex)
	local params = terralib.newlist{
		__ducktype__ = {path = {"Any"}, name = "Any"},
		__varargs__ = {path = {"Vararg"}, name = "Vararg"}
	}
	if lex:nextif("where") then
		lex:expect("{") 
		repeat      
			local param = lex:expect(lex.name).value
			params[param] = process_single_constraint(lex)    
		until not lex:nextif(",")                                
		lex:expect("}")                                
	end        
	return params
end

function isclasstemplate(templ)
	return templ.classname~=nil
end

function isnamespacedfunctiontemplate(templ)
	return templ.classname==nil and #templ.path > 1
end

function isfreefunctiontemplate(templ)
	return templ.classname==nil and #templ.path == 1
end

function isstaticmethod(templ,localenv)
	return #templ.path>1 and terralib.types.istype(localenv(templ.path,1))
end

function isvarargstemplate(templ)
	local n = #templ.params
	return templ.params[n].typename == "__varargs__"
end

return conceptlang