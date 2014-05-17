local env=env
local cfg,grid={},env.grid
local keys={}
local maxvalsize=20
cfg._backup=nil

function cfg.show_cfg(name)
	local rows={{'Name','Value','Default','Class','Available Values','Description'}}
	if name then
		local v=cfg[name]
		table.insert(rows,{name,string.from(v.value),string.from(v.default),v.range or '*',v.class,v.desc})
	else
		for _,k in ipairs(keys) do
			table.insert(rows,{k,string.from(cfg[k].value),string.from(cfg[k].default),cfg[k].class,cfg[k].range or '*',cfg[k].desc})
		end
	end
	grid.sort(rows,"Class,Name",true)
	grid.print(rows)
end

function cfg.init(name,defaultvalue,validate,class,desc,range)
	name=name:upper()
	if cfg[name] then 
		return print("Error : Environment parameter["..name.."] has been defined in "..cfg[name].src.."!")
	end
	if not cfg[name] then cfg[name]={} end
	table.insert(keys,name)
	cfg[name]={
		value=defaultvalue,
		default=defaultvalue,
		func=validate,
		class=class,
		desc=desc,
		range=range,
		org=defaultvalue,
		src=env.callee()
	}
	if maxvalsize<tostring(defaultvalue):len() then
		maxvalsize=tostring(defaultvalue):len() 
	end
end

function cfg.get(name)
	name=name:upper()
	if not cfg[name] then return print("["..name.."] setting does not exist!")	end	
	return cfg[name].value
end

function cfg.temp(name,value,backup)
	name=name:upper()
	if not cfg[name] then return end	
	if backup or cfg[name].prebackup then
		cfg[name].org=cfg[name].value
	end
	cfg[name].prebackup=backup
	cfg[name].value=value
end

function cfg.set(name,value,backup)
	--res,err=pcall(function()
	if not name then return cfg.show_cfg() end
	name=name:upper()
	if not cfg[name] then return print("Cannot set ["..name.."], the parameter does not exist!") end
	if not value then return cfg.show_cfg(name) end
	if tostring(value):upper()=="DEFAULT" then
		return cfg.set(name,cfg[name].default)
	elseif tostring(value):upper()=="BACK" then
		return cfg.restore(name)
	end

	local range= cfg[name].range
	if range and range ~='' then
		local lower,upper=range:match("([%-%+]?%d+)%s*%-%s*([%-%+]?%d+)")
		if lower then
			value,lower,upper=tonumber(value),tonumber(lower),tonumber(upper)
			if not value or not (value>=lower and value<=upper) then
				return print("Invalid value for '"..name.."', it should be "..range)
			end
		elseif range:find(",") then
			local match=0
			local value=value:lower()
			for k in range:gmatch('([^,%s]+)') do
				if value==k:lower() then
					match=1
				end
			end
			if match==0 then
				return print("Invalid value for '"..name.."', it should be one of the following values: "..range)
			end
		end
	end

	if cfg[name].func then
	   value=cfg[name].func(name,value) 
	   if value==nil then return end
	end

	cfg.temp(name,value,backup)
	if maxvalsize<tostring(value):len() then
		maxvalsize=tostring(value):len() 
	end
	
end

function cfg.doset(...) 
	local args={...}
	if #args==0 then
		cfg.show_cfg()
	end
	for i=1,#args,2 do
		cfg.set(args[i],args[i+1],true)
	end
end

function cfg.restore(name)
	if not name then
		if not cfg._backup then return end
		for k,v in pairs(cfg._backup) do
			if v.value~=cfg[k].value then
				cfg.set(k,v.value)
				cfg[k]=v
			end
		end
		cfg._backup=nil
		return
	end
	name=name:upper()
	if not cfg[name] or cfg[name].org==nil then return end
	cfg.set(name,cfg[name].org)
end

function cfg.tester()
	
end

function cfg.backup()
	if cfg._backup then return end
	cfg._backup={}
	for k,v in pairs(cfg) do
		if k==k:upper() and type(v)=="table" then
			cfg._backup[k]={}
			for item,value in pairs(v) do
				cfg._backup[k][item]=value
			end
		end
	end
end

env.set_command(nil,'SET',"Set environment parameters. Usage: set <name1> [<value1|DEFAULT|BACK> [name2 ...]]",cfg.doset,false,99)

return cfg