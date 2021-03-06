--init a global function to store CLI variables
local _G = _ENV or _G

local reader,coroutine,os,string,table,math,io,select,xpcall,pcall=reader,coroutine,os,string,table,math,io,select,xpcall,pcall

local getinfo, error, rawset, rawget,math = debug.getinfo, error, rawset, rawget,math

--[[
local global_vars,global_source,env={},{},{}
_G['env']=env
local global_meta=getmetatable(_G) or {}
function global_meta.__newindex(self,key,value) rawset(global_vars,key,value) end
function global_meta.__index(self,key) return rawget(global_vars,key) or rawget(_G,key) end
function global_meta.__newindex(self,key,value) rawset(global_vars,key,value) end
function global_meta.__pairs(self) return pairs(global_vars) end
global_meta.__call=global_meta.__newindex

debug.setmetatable(env,global_meta)
setmetatable(_G,global_meta)
--]]


local env=setmetatable({},{
    __call =function(self, key, value)
            rawset(self,key,value)
            _G[key]=value
        end,
    __index=function(self,key) return _G[key] end,
    __newindex=function(self,key,value) self(key,value) end
})
_G['env']=env

local mt = getmetatable(_G)

if mt == nil then
    mt = {}
    setmetatable(_G, mt)
end

mt.__declared = {}

local debug_mode=os.getenv("DEBUG_MODE")
mt.__newindex = function (t, n, v)
    if not mt.__declared[n] and env.WORK_DIR then
        if debug_mode and env.IS_ENV_LOADED and n~='reset_input' and n:upper()~=n then print('Detected unexpected global var "'..n..'" with', debug.traceback()) end
        rawset(mt.__declared, n,env.callee(5))
    end
    rawset(t, n, v)
end

env.globals=mt.__declared


local function abort_thread()
    if coroutine.running () then
        debug.sethook()
        --print(env.CURRENT_THREAD)
        --print(debug.traceback())
    end
end

_G['TRIGGER_EVENT']=function(key_event,key_name)
    local event={'keydown','keycode','uchar','isfunc','repeat','isalt','isctrl','issift'}
    for i,j in ipairs(event) do event[j],event[i]=key_event[i] end
    event.name=tostring(key_name)
    env.safe_call(env.event and env.event.callback,5,"ON_KEY_EVENT",event,key_event)
    return event.isbreak and 2 or 0
end

local function pcall_error(e)
    return tostring(e) .. '\n' .. debug.traceback()
end

function env.ppcall(f, ...)
    return xpcall(f, pcall_error, ...)
end

local writer,_THREADS=writer,{_clock={}}
env.RUNNING_THREADS=_THREADS
local dbcli_stack,dbcli_cmd_history={},{}
local dbcli_current_item=dbcli_stack
env.__DBCLI__STACK,env.__DBCLI__CMD_HIS=dbcli_stack,dbcli_cmd_history
local function push_stack(cmd)
    local threads=_THREADS
    local thread,isMain,index=env.register_thread()
    local item,callee={},env.callee(4)
    local parent=dbcli_stack[index-1]
    if parent then
        for k,v in pairs(parent) do
            if type(k) ~="number" then item[k]=v end
        end
    end

    dbcli_stack[index],dbcli_current_item,dbcli_stack.last=item,item,index

    item.clock,item.command,item.callee,item.parent,item.level,item.id=_THREADS._clock[index],cmd,callee,parent,index,thread

    item=dbcli_stack[index+1]
end

local function push_history(cmd)
    cmd=cmd:gsub("%s+"," "):gsub("^%+",""):sub(1,200)
    dbcli_cmd_history[#dbcli_cmd_history+1]=("%d: %s%s"):format(dbcli_current_item.level, string.rep("   ",dbcli_current_item.level-1),cmd)
    while #dbcli_cmd_history>1000 do
        table.remove(dbcli_cmd_history,1)
    end
end

function env.print_stack()
    local stack=table.concat({"CURRENT_ID:",tostring(dbcli_current_item.id),"   CURRENT_LEVEL:",dbcli_current_item.level,"   CURRENT_COMMAND:",dbcli_current_item.command}," ")
    stack=stack..'\n'..table.dump(dbcli_stack)
    stack=stack..'\n'.."Historical Commands:\n===================="
    stack=stack..'\n'..table.concat(dbcli_cmd_history,'\n')
    print(stack)
end

--Build command list
env._CMDS=setmetatable({___ABBR___={}},{
    __index=function(self,key)
        if not key then return nil end
        key=key:upper()
        local abbr=rawget(self,'___ABBR___')
        local value=rawget(self,key) or rawget(abbr,key)
        return value and rawget(abbr,value) or value
    end,

    __newindex=function(self,key,value)
        local abbr=rawget(self,'___ABBR___')
        if not key then return end
        if rawget(abbr,key) then
            if type(value)=="table" then
                rawset(abbr,key,value)
            else
                local cmd=rawget(abbr,key)
                rawset(abbr,key,value)
                if type(cmd)=="string" then
                    for k,v in pairs(abbr) do
                        if v==cmd then rawset(abbr,k,value) end
                    end
                end
            end
        else
            rawset(self,key,value)
        end
    end,

    __pairs=function(self)
        local p,abbr={},rawget(self,'___ABBR___')
        for k,v in pairs(abbr) do
            if not abbr[v] then p[k]=v end
        end
        return pairs(p)
    end
})

--
env.space="    "
local _CMDS=env._CMDS

local previous_prompt
function env.set_subsystem(cmd,prompt)
    if cmd~=nil then
        env._SUBSYSTEM=cmd
        env.set_prompt(cmd,prompt or cmd,false,9)
    else
        env._SUBSYSTEM,_G._SUBSYSTEM=nil,nil
        env.set_prompt(cmd,nil,false,9)
    end
end

local terminator_patt,terminator='%f[<%w]<<(%S+)[ \r]*$'
function env.check_cmd_endless(cmd,other_parts)
    if not _CMDS[cmd] then
        return true,other_parts
    end
    --print(other_parts,debug.traceback())
    if terminator then 
        if other_parts and other_parts:trim():sub(-#terminator)==terminator then
            return true,other_parts
        end
        return false,other_parts
    elseif not _CMDS[cmd].MULTI then
        return true,other_parts and env.COMMAND_SEPS.match(other_parts)
    elseif type(_CMDS[cmd].MULTI)=="function" then
        return _CMDS[cmd].MULTI(cmd,other_parts)
    elseif _CMDS[cmd].MULTI=='__SMART_PARSE__' then
        return env.smart_check_endless(cmd,other_parts,_CMDS[cmd].ARGS)
    end

    local match,typ,index = env.COMMAND_SEPS.match(other_parts)
    --print(match,other_parts)
    if index==0 then
        return false,other_parts
    end
    return true,match
end

function env.smart_check_endless(cmd,rest,from_pos)
    local args=env.parse_args(from_pos,rest)
    if #args==0 then return true,env.COMMAND_SEPS.match(rest) end
    for k=#args,1,-1 do
        if not env.check_cmd_endless(args[k]:upper(),table.concat(args,' ',k+1)) then
            return false,rest
        end
    end
    return true,env.COMMAND_SEPS.match(rest)
end

local function _new_command(obj,cmd,help_func,call_func,is_multiline,parameters,is_dbcmd,allow_overriden,is_pipable,color)
    local abbr={}

    if not parameters then
        env.raise("Incompleted command["..cmd.."], number of parameters is not defined!")
    end

    if type(cmd)~="table" then cmd={cmd} end
    local tmp=cmd[1]:upper()

    for i=1,#cmd do
        cmd[i]=cmd[i]:upper()
        if _CMDS[cmd[i]] then
            if _CMDS[cmd[i]].ISOVERRIDE~=true then
                env.raise("Command '"..cmd[i].."' is already defined in ".._CMDS[cmd[i]]["FILE"])
            else
                _CMDS[cmd[i]]=nil
            end
        end
        if i>1 then table.insert(abbr,cmd[i]) end
    end

    for i=1,#cmd do _CMDS.___ABBR___[cmd[i]]=tmp  end

    cmd=tmp

    local src=env.callee()
    local desc=help_func
    local args= obj and {obj,cmd} or {cmd}
    if type(help_func) == "function" then
        desc=help_func(table.unpack(args))
    elseif type(help_func) =="table" then
        desc,help_func=help_func[1],help_func[2]
        if not help_func then help_func=desc end
        if type(desc)=="function" then
            desc=desc(table.unpack(args))
        end
    end

    if type(desc)=="string" then
        desc = desc:gsub("^%s*[\n\r]+",""):match("([^\n\r]+)")
    elseif desc then
        env.warn(cmd..': Unexpected command definition, the description should be a function or string, but got '..type(desc))
        desc=nil
    end

    _CMDS[cmd]={
        OBJ       = obj,          --object, if the connected function is not a static function, then this field is used.
        FILE      = src,          --the file name that defines & executes the command
        DESC      = desc,         --command short help without \n
        HELPER    = help_func,    --command detail help, it is a function
        FUNC      = call_func,    --command function
        MULTI     = is_multiline or false,
        ABBR      = table.concat(abbr,','),
        ARGS      = parameters,
        DBCMD     = is_dbcmd,
        COLOR     = color,
        ISOVERRIDE= allow_overriden,
        ISPIPABLE = is_pipable
    }
end

function env.set_command(...)
    local tab,siz=select(1,...),select('#',...)
    if siz==1 and type(tab)=="table" and tab.cmd then
        return _new_command(tab.obj,tab.cmd,tab.help_func,tab.call_func,tab.is_multiline,tab.parameters,tab.is_dbcmd,tab.allow_overriden,tab.is_pipable,tab.color)
    else
        return _new_command(...)
    end
end

function env.rename_command(name,new_name)
    local info=_CMDS[name]
    env.checkerr(info,"No such command: "..name)
    for k,v in pairs(_CMDS.___ABBR___) do
        if _CMDS[k]==info then
            _CMDS[k]=nil 
        end
    end
    if type(new_name)=="string" then
        info.ABBR=""
        new_name={new_name}
    else
        info.ABBR=table.concat(new_name,",",2):upper()
    end
    
    for k,v in ipairs(new_name) do
        _CMDS.___ABBR___[v:upper()]=new_name[1]:upper()
    end
    _CMDS[new_name[1]:upper()]=info
end

function env.get_command_by_source(list)
    local cmdlist={}
    if type(list)=="string" then list={list} end
    for k,v in pairs(_CMDS.___ABBR___) do
        while type(v)=="string" do v=_CMDS.___ABBR___[v] end
        for _,name in ipairs(list) do
            name=name=="default" and env.callee():match("([^\\/]+)#") or name
            if v.FILE:lower():match('[\\/]'..name:lower()..'#') then cmdlist[k]=1 end
        end
    end
    return cmdlist
end


function env.remove_command(cmd)
    cmd=cmd:upper()
    if not _CMDS[cmd] then return end
    local src=env.callee()
    --if src:gsub("#%d+","")~=_CMDS[cmd].FILE:gsub("#%d+","") then
    --    env.raise("Cannot remove command '%s' from %s, it was defined in file %s!",cmd,src,_CMDS[cmd].FILE)
    --end

    _CMDS[cmd]=nil
    for k,v in pairs(_CMDS.___ABBR___) do
        if(v==cmd) then _CMDS.___ABBR___[k]=nil end
    end
end

function env.callee(idx)
    if type(idx)~="number" then idx=3 end
    local info=getinfo(idx)
    if not info then return nil end
    local src=info.short_src
    if src:lower():find(env.WORK_DIR:lower(),1,true) then
        src=src:sub(#env.WORK_DIR+1)
    end
    return src:gsub("%.%w+$","#"..info.currentline)
end

function env.format_error(src,errmsg,...)
    if not errmsg then return end
    errmsg=(tostring(errmsg) or "")
    local HIR,NOR,count="",""
    if env.ansi and env.set and env.set.exists("ERRCOLOR") then
        HIR,NOR=env.ansi.get_color(env.set.get("ERRCOLOR")),env.ansi.get_color('NOR')
        errmsg=errmsg:strip_ansi()
    end
    env.log_debug("ERROR",errmsg)
    errmsg,count=errmsg:gsub('^.-(%u%u%u%-%d%d%d%d%d)','%1') 
    if count==0 then
        errmsg=errmsg:gsub('^.*%s([^%: ]+Exception%:%s*)','%1'):gsub(".*[IS][OQL]+Exception:%s*","")
    end
    errmsg=errmsg:gsub("\n%s+at%s+.*$","")
    errmsg=errmsg:gsub("^.*000%-00000%:%s*",""):gsub("%s+$","")
    if src then
        local name,line=src:match("([^\\/]+)%#(%d+)$")
        if name then
            name=name:upper():gsub("_",""):sub(1,3)
            errmsg=string.format("%s-%05i: %s",name,tonumber(line),errmsg)
        end
    end
    if select('#',...)>0 then errmsg=errmsg:format(...) end
    return errmsg=="" and errmsg or HIR..errmsg..NOR
end

function env.warn(...)
    local str,count=env.format_error(nil,...)
    if str and str~='' then print(str,'__BYPASS_GREP__') end
end

function env.raise_error(...)
    local str=env.format_error(nil,...)
    return error('000-00000:'..str)
end

function env.raise(index,...)
    local stack
    if type(index)~="number" then
        index,stack=3,{index,...}
    else
        stack={...}
    end
    table.insert(stack,1,(env.callee(index)))
    local str=env.format_error(table.unpack(stack))
    return error(str)
end

function env.checkerr(result,index,msg,...)
    local stack
    if result then return end
    if type(index)~="number" then
        stack={4,index,msg,...}
    else
        stack={index+3,msg,...}  
    end
    if type(stack[2])=="function" then stack[2]=stack[2](table.unpack(stack,3)) end
    env.raise(table.unpack(stack))
end

function env.checkhelp(arg)
    env.checkerr(arg,env.helper.helper,env.CURRENT_CMD)
end

local co_stacks={}
local function _exec_command(name,params)
    local result
    local cmd=_CMDS[name:upper()]
    if not cmd then
        return env.warn("No such comand '%s'!",name)
    end
    if not cmd.FUNC then return end
    

    local funs=type(cmd.FUNC)=="table" and cmd.FUNC or {cmd.FUNC}
    local args= cmd.OBJ and {1,cmd.OBJ,table.unpack(params)} or {1,table.unpack(params)}
    for _,func in ipairs(funs) do
        local co,_,index=env.register_thread()
        co=co_stacks[index+1]
        if not co or coroutine.status(co)=='dead' then
            co=coroutine.create(function(f) while f do f=coroutine.yield(f[1](table.unpack(f,2))) end end)
            --print(co)
        end
        env.register_thread(co)
        args[1]=func
        local res={coroutine.resume(co,args)}
        env.register_thread()
        --local res = {pcall(func,table.unpack(args))}
        if not res[1] then
            result=res
            env.log_debug("CMD",res[2])
            env.warn(res[2])
        elseif not result then
            result=res
        end
    end

    if not result[1] then error('000-00000:') end
    
    return table.unpack(result)
end


function env.register_thread(this,isMain)
    local threads=_THREADS
    if not this then this,isMain=coroutine.running() end
    if isMain then threads[this],threads[1]=1,this end
    local index,clock=threads[this],threads._clock
    if not index then
        index=#threads+1
        threads[this],threads[index],clock[index]=index,this,os.clock()
    else
        for i=index+1,#threads do 
            threads[i],threads[threads[i]]=nil,nil
        end
        if not clock[index] then clock[index]=os.clock() end
    end
    co_stacks[index]=this
    return this,isMain,index
end

function env.exec_command(cmd,params,is_internal,arg_text)
    local name=cmd:upper()
    local event=env.event and env.event.callback
    local this,isMain,index=env.register_thread()
    is_internal,arg_text=is_internal or false,arg_text or ""
    env.CURRENT_CMD=name
    arg_text=cmd.." "..arg_text
    if event then
        if isMain then
            if writer then
                env.ROOT_CMD=name
                writer:print(env.ansi.mask("NOR",""))
                writer:flush()
            end
            env.log_debug("CMD",name,params)
        end
        
        if event and not is_internal then
            name,params,is_internal,arg_text=table.unpack((event("BEFORE_COMMAND",{name,params,is_internal,arg_text}))) 
        end
    end
    local res={pcall(_exec_command,name,params,arg_text)}
    if event and not is_internal then 
        event("AFTER_COMMAND",name,params,res[2],is_internal,arg_text)
    end
    if not isMain and not res[1] and (not env.set or env.set.get("OnErrExit")=="on") then error() end

    local clock=math.floor((os.clock()-_THREADS._clock[index])*1e3)/1e3

    if event and not is_internal then
        event("AFTER_SUCCESS_COMMAND",name,params,res[2],is_internal,arg_text,clock)
    end

    if isMain then
        _THREADS._clock[index]=nil
        if env.PRI_PROMPT=="TIMING> " then
            env.CURRENT_PROMPT=string.format('%06.2f',clock)..'> '
            env.MTL_PROMPT=string.rep(' ',#env.CURRENT_PROMPT)
        end
    end
    return table.unpack(res,2)
end

local is_in_multi_state=false
local curr_stmt=""
local multi_cmd

local cache_prompt,fix_prompt

local prompt_stack={_base="SQL"}

function env.set_prompt(class,default,is_default,level)
    if default then
        if not env._SUBSYSTEM  then default=default:upper() end
        if env.ansi then default=env.ansi.convert_ansi(default) end
    end
    class=class or "default"
    level=level or (class=="default" or default==prompt_stack._base) and 0 or 3
    if prompt_stack[class] and prompt_stack[class]>level then prompt_stack[prompt_stack[class]]=nil end
    prompt_stack[level],prompt_stack[class]=default,level

    for i=9,0,-1 do
        if prompt_stack[i] then
            default=prompt_stack[i]
            break
        end
    end

    if env._SUBSYSTEM or (default and not default:match("[%w]%s*$")) then 
        env.PRI_PROMPT=default 
    else
        env.PRI_PROMPT=(default or "").."> "
    end

    env.CURRENT_PROMPT,env.MTL_PROMPT=env.PRI_PROMPT,(" "):rep(#env.PRI_PROMPT)
    return default
end

function env.pending_command()
    return curr_stmt and curr_stmt~=""
end

function env.modify_command(_,key_event)
    --print(key_event.name)
    if key_event.name=="CTRL+C" or key_event.name=="CTRL+D" then
        if env.IS_ASKING then return end
        if env.pending_command() then
            multi_cmd,curr_stmt=nil,nil
        end
        env.CURRENT_PROMPT=env.PRI_PROMPT
        local prompt,reset=env.PRI_PROMPT,""

        if env.ansi then
            local prompt_color="%s%s"..env.ansi.get_color("NOR").."%s"
            prompt=prompt_color:format(env.ansi.get_color("PROMPTCOLOR"),prompt,env.ansi.get_color("COMMANDCOLOR"))
            reset=env.ansi.get_color("KILLBL")
        end
        reader:resetPromptLine(prompt,"",0)
        env.printer.write(reset)
    elseif key_event.name=="CTRL+BACK_SPACE" or key_event.name=="SHIFT+BACK_SPACE" then --shift+backspace
        reader:invokeMethod("deletePreviousWord")
        key_event.isbreak=true
    elseif key_event.name=="CTRL+LEFT" or key_event.name=="SHIFT+LEFT" then --ctrl+arrow_left
        reader:invokeMethod("previousWord")
        key_event.isbreak=true
    elseif key_event.name=="CTRL+RIGHT" or key_event.name=="SHIFT+RIGHT" then --ctrl+arrow_right
        reader:invokeMethod("nextWord")
        key_event.isbreak=true
    end
end

function env.parse_args(cmd,rest,is_cross_line)
    --deal with the single-line commands
    local arg_count,terminator,terminator_str
    if type(cmd)=="number" then
        arg_count=cmd+1
    else
        if not cmd then
            cmd,rest=env.COMMAND_SEPS.match(rest):match('(%S+)%s*(.*)')
            cmd = cmd and cmd:upper() or "_unknown_"
            print(debug.traceback())
        end

        env.checkerr(_CMDS[cmd],'Unknown command "'..cmd..'"!')
        arg_count=_CMDS[cmd].ARGS
    end

    if rest then rest=rest:gsub("%s+$","") end
    if rest=="" then 
        rest = nil 
    elseif rest then
        terminator=rest:match('([^\r\n]*)'):match(terminator_patt)
        if terminator then 
            terminator_str='<<'..terminator
            rest=rest:trim()
            if rest:sub(-#terminator-1)=='\n'..terminator then
                rest=rest:sub(1,-#terminator-2)
            end
            if rest:sub(1,#terminator_str)==terminator_str then
                rest=rest:sub(#terminator_str+1):trim()
                arg_count=math.min(2,arg_count)
            end
        end
    end
    
    local args={}
    if arg_count == 1 then
        args[#args+1]=cmd..(rest and #rest> 0 and (" "..rest) or "")
    elseif arg_count == 2 then
        args[#args+1]=rest
    elseif rest then
        local piece=""
        local quote='"'
        local is_quote_string = false
        local count=#args
        for i=1,#rest,1 do
            local char=rest:sub(i,i)
            if char=='<' and terminator and rest:sub(i,i+#terminator_str-1)==terminator_str then
                rest=rest:sub(i+#terminator_str):trim()
                if piece~="" then args[#args+1],piece=piece,"" end
                args[#args+1]=rest
                break
            end
            
            if is_quote_string then--if the parameter starts with quote
                if char ~= quote then
                    piece = piece .. char
                elseif rest:sub(i+1,i+1):match("%s") or #rest==i then
                    --end of a quote string if next char is a space
                    args[#args+1]=(piece..char):gsub('^"(.*)"$','%1')
                    piece,is_quote_string='',false
                else
                    piece=piece..char
                end
            else
                if char==quote then
                    --begin a quote string, if its previous char is not a space, then bypass
                    is_quote_string,piece = true,piece..quote
                elseif not char:match("%s") then
                    piece = piece ..char
                elseif piece ~= '' then
                    args[#args+1],piece=piece,''
                end
            end

            if count ~= #args then
                count=#args
                local name=args[count]:upper()
                local is_multi_cmd=char~=quote and is_cross_line==true and _CMDS[name] and _CMDS[name].MULTI
                if count>=arg_count-2 or is_multi_cmd then--the last parameter
                    piece=rest:sub(i+1):gsub("^(%s+)",""):gsub('^"(.*)"$','%1')
                    if is_multi_cmd and _CMDS[name].ARGS==1 then
                        args[count],piece=args[count]..' '..piece,''
                    elseif piece~='' then
                        args[count+1],piece=piece,''
                    end
                    break
                end
            end
        end
        --If the quote is not in couple, then treat it as a normal string
        if piece:sub(1,1)==quote then
            for s in piece:gmatch('(%S+)') do
                args[#args+1]=s
            end
        elseif not piece:match("^%s*$") then
            args[#args+1]=piece
        end
    end
    return args,cmd
end

function env.force_end_input(exec,is_internal)
    if curr_stmt and multi_cmd then
        local text,stmt=curr_stmt,{multi_cmd,env.parse_args(multi_cmd,curr_stmt,true)}
        multi_cmd,curr_stmt=nil,nil
        env.CURRENT_PROMPT=env.PRI_PROMPT
        if exec~=false then
            env.exec_command(stmt[1],stmt[2],is_internal,text)
        else
            return stmt[1],stmt[2]
        end
    end
    multi_cmd,curr_stmt=nil,nil
    return
end

local function _eval_line(line,exec,is_internal,not_skip)
    if type(line)~='string' or line:gsub('%s+','')=='' then return end
    local subsystem_prefix=""
    --Remove BOM header
    if not env.pending_command() then
        push_stack(line)
        subsystem_prefix=env._SUBSYSTEM and (env._SUBSYSTEM.." ") or ""
        local cmd=env.parse_args(2,line)[1]
        if dbcli_current_item.skip_subsystem and not not_skip then
            subsystem_prefix=""
        elseif cmd:sub(1,1)=='.' and _CMDS[cmd:upper():sub(2)] then
            subsystem_prefix=""
            dbcli_current_item.skip_subsystem=true
            line=line:gsub("^[ %.]+","")
        elseif cmd:lower()==subsystem_prefix:lower() then
            subsystem_prefix=""
        end

        if subsystem_prefix~="" then
            if exec~=false then
                line=line:gsub('%z+$','')
                env.exec_command(env._SUBSYSTEM,{line})
                return;
            else
                return cmd,{line}
            end
        end

        line=line:gsub('^[%s%z\128-\255 \t]+','')
        if line:match('^([^%w])') then
            local cmd=""
            for i=math.min(#line,5),1,-1 do
                cmd=line:sub(1,i)
                if _CMDS[cmd] then
                    if #line>i and not line:sub(i+1,i+1):find('%s') then
                        line=cmd..' '..line:sub(i+1)
                    end
                    break
                end
            end
        end
        
    end

    local done
    local function check_multi_cmd(lineval)
        curr_stmt = curr_stmt ..lineval
        done,curr_stmt=env.check_cmd_endless(multi_cmd,curr_stmt)
        if done or is_internal then
            return env.force_end_input(exec,is_internal)
        end
        curr_stmt = curr_stmt .."\n"
        return multi_cmd
    end
    
    local cmd,rest,end_mark

    local rest,pipe_cmd,param = (' '..line):match('^(.*[^|])|%s*(%w+)(.*)$')
    if pipe_cmd and _CMDS[pipe_cmd:upper()] and _CMDS[pipe_cmd:upper()].ISPIPABLE==true then
        param=env.COMMAND_SEPS.match(param)
        if multi_cmd then
            param,multi_cmd=param..' '..multi_cmd..' '..curr_stmt,nil
        end
        pipe_cmd=pipe_cmd..' '..param..rest
        return eval_line(pipe_cmd,exec,true,not_skip)
    end

    if multi_cmd then return check_multi_cmd(line) end
    
    line,end_mark=env.COMMAND_SEPS.match(line)
    cmd,rest=line:match('^%s*(%S+)%s*(.*)')
    if not rest then return end
    rest=rest..(end_mark or "")
    if not cmd or cmd=="" then return end
    cmd=cmd:upper()
    env.CURRENT_CMD=cmd
    terminator=nil
    if not (_CMDS[cmd]) then
        return env.warn("No such command '%s', please type 'help' for more information.",cmd)
    elseif not end_mark and not rest:find('\n',1,true) then 
        terminator=rest:match(terminator_patt)
        if terminator then
            terminator,multi_cmd,curr_stmt,env.CURRENT_PROMPT='\n'..terminator,cmd,"",env.MTL_PROMPT
            return check_multi_cmd(rest)
        end
    end
    
    if _CMDS[cmd].MULTI then --deal with the commands that cross-lines
        multi_cmd=cmd
        env.CURRENT_PROMPT=env.MTL_PROMPT
        curr_stmt = ""
        return check_multi_cmd(rest)
    end

    --print('Command:',cmd,table.concat (args,','))
    rest=env.COMMAND_SEPS.match(rest)
    local args=env.parse_args(cmd,rest)
    if exec~=false then
        env.exec_command(cmd,args,is_internal,rest)
    else
        return cmd,args
    end
end

function env.eval_line(lines,is_internal,is_skip)
    if env.event then
        lines=env.event.callback('BEFORE_EVAL',{lines})[1]
    end
    local stack=lines:split("[\n\r]+")
    for index,line in ipairs(stack) do
        if index==#stack then
            return _eval_line(line,is_internal,is_skip)
        else
            _eval_line(line,false,false)
        end
    end
end

function env.testcmd(command)
    env.checkerr(command,"Usage: -p <other command>")
    local cmd,args=env.eval_line(command,false,true)
    if not cmd then return end
    print("Command    : "..cmd.."\nParameters : "..#args..' - '..(_CMDS[cmd].ARGS-1).."\n============================")
    for k,v in ipairs(args) do
        print(string.format("%-2s = %s",k,v))
    end
end

function env.safe_call(func,...)
    if not func then return end
    local res,rtn=pcall(func,...)
    if not res then
        return env.warn(tostring(rtn):gsub(env.WORK_DIR,""))
    end
    return rtn
end

function env.set_endmark(name,value)
    if value:gsub('[\\%%]%a',''):match('[%w]') then return print('The delimiter cannot be alphanumeric characters. ') end;
    local p={value:gsub("\\+",'\\'):match("^([^, ]+)( *,? *(.*))$")}
    table.remove(p,2)
    for k,v in ipairs(p) do
        p[k]=v:gsub('\\(%w)',function(s) return s=='n' and '\n' or s=='r' and '\r' or s=='t' and '\t' or '\\'..s end)
        local c=p[k]:gsub("(.?)([%$%(%)%^%.])",function(a,b) return a..(a=="%" and "" or "%")..b end)
        p["p"..k]="^(.-)[ \t]*("..c..(#(c:gsub("%%",""))==1 and "+" or "")..")[ \t%z]*$"
        p[k]=p[k]:gsub("([^%+%*%?%-])[%+%*%?%-]","%1"):gsub("%%.","")
    end
    if p[2]=="" then p[2],p["p2"]=p[1],p["p1"] end

    env.COMMAND_SEPS=p
    env.COMMAND_SEPS.match=function(s)
        local c,r=s:match(p["p1"])
        if c then return c,r,1 end
        c,r=s:match(p["p2"])
        if c then return c,r,2 end
        if s:sub(-1)=='\0' then
            return s:sub(1,-2),'\0',2
        end
        return s,nil,0
    end
    return value
end

local end_marks=(";,\\n%s*/")
env.set_endmark(nil,end_marks)

function env.check_comment(cmd,other_parts)
    if not other_parts:find("*/",1,true) then
        return false,other_parts
    end
    return true,other_parts
end

local print_debug
local debug_group={ALL="all"}
function env.log_debug(name,...)
    name=name:upper()
    if not debug_group[name] then debug_group[name]=env.callee(3) end
    if not print_debug or env.set.get('debug')=="off" then return end
    local value=env.set.get('debug'):upper()
    local args={'['..name..']'}
    for i=1,select('#',...) do
        local v=select(i,...)
        if v==nil then
            args[i+1]='nil'
        elseif type(v)=="table" then 
            args[i+1]=table.dump(v)
        else
            args[i+1]=v
        end
    end
    if value=="all" or value==name then print_debug(table.unpack(args)) end
end

function set_debug(name,value)
    value=value:upper()
    if env.grid then
        local rows=env.grid.new()
        rows:add{"Name","Source","Enabled"}
        for k,v in pairs(debug_group) do
            rows:add{k,v,k==value and "Yes" or "No"}
        end
        rows:sort(1,true)
        rows:print()
    end
    return value
end

local function set_cache_path(name,path)
    path=env.join_path(path,"")
    env.checkerr(os.exists(path)=='directory',"No such path: "..path)
    env['_CACHE_BASE'],env["_CACHE_PATH"]=path,path
    return path
end

function env.onload(...)
    env.__ARGS__={...}
    env.IS_ENV_LOADED=false
    for _,v in ipairs({'jit','ffi','bit'}) do   
        if v=="jit" then
            table.new=require("table.new")
            table.clear=require("table.clear")
            env.jit.on()
            env.jit.profile=require("jit.profile")
            env.jit.util=require("jit.util")
            env.jit.opt.start(3,"maxsnap=4096","maxmcode=1024")
        elseif v=='ffi' then
            env.ffi=require("ffi")
        end
    end

    env.init=require("init")
    env.init.init_path()

    os.setlocale('',"all")
    env.set_command(nil,"EXIT","#Exit environment, including variables, modules, etc",env.exit,false,1)
    env.set_command(nil,"RELOAD","Reload environment, including variables, modules, etc",env.reload,false,1)
    env.set_command(nil,"LUAJIT","#Switch to luajit interpreter, press Ctrl+Z to exit.",function() os.execute(('"%slib%sx86%sluajit"'):format(env.WORK_DIR,env.PATH_DEL,env.PATH_DEL)) end,false,1)
    env.set_command(nil,"-P","#Test parameters. Usage: -p <command> [<args>]",env.testcmd,'__SMART_PARSE__',2)

    env.init.onload()
    
    env.set_prompt(nil,prompt_stack._base,nil,0)
    if env.set and env.set.init then
        env.set.init({"Prompt","SQLPROMPT","SQLP"},prompt_stack._base,function(n,v,d) return env.set_prompt(n,v,d,3) end,
                  "core","Define command's prompt, if value is 'timing' then will record the time cost(in second) for each execution.")
        env.set.init({"sqlterminator","COMMAND_ENDMARKS"},end_marks,env.set_endmark,
                  "core","Define the symbols to indicate the end input the cross-lines command. ")
        env.set.init("Debug",'off',set_debug,"core","Indicates the option to print debug info, 'all' for always, 'off' for disable, others for specific modules.")
        env.set.init("OnErrExit",'on',nil,"core","Indicates whether to continue the remaining statements if error encountered.","on,off")
        env.set.init("TEMPPATH",'cache',set_cache_path,"core","Define the dir to store the temp files.","*")
        print_debug=print
    end
    if  env.ansi and env.ansi.define_color then
        env.ansi.define_color("Promptcolor","HIY","ansi.core","Define prompt's color, type 'ansi' for more available options")
        env.ansi.define_color("ERRCOLOR","HIR","ansi.core","Define color of the error messages, type 'ansi' for more available options")
        env.ansi.define_color("PromptSubcolor","HIM","ansi.core","Define the prompt color for subsystem, type 'ansi' for more available options")
        env.ansi.define_color("commandcolor","HIC","ansi.core","Define command line's color, type 'ansi' for more available options")
    end
    if env.event then
        env.event.snoop("ON_KEY_EVENT",env.modify_command)
        env.event.callback("ON_ENV_LOADED")
    end

    set_command(nil,"/*"    ,   '#Comment',        nil   ,env.check_comment,2)
    set_command(nil,"--"    ,   '#Comment',        nil   ,false,2)
    set_command(nil,"REM"   ,   '#Comment',        nil   ,false,2)
    env.reset_title()
    --load initial settings
    for _,v in ipairs(env.__ARGS__) do
        if v:sub(1,2) == "-D" then
            local key=v:sub(3):match("^([^=]+)")
            local value=v:sub(4+#key)
            java.system:setProperty(key,value)
        else
            v=v:gsub("="," ",1)
            local args=env.parse_args(2,v)
            if args[1] and _CMDS[args[1]:upper()] then
                env.eval_line(v..'\0')
            end
        end
    end
    env.IS_ENV_LOADED=true
end

function env.unload()
    if env.event then env.event.callback("ON_ENV_UNLOADED") end
    local e,msg=pcall(env.init.unload,init.module_list,env)
    if not e then print(msg) end
    env.init=nil
    package.loaded['init']=nil
    _CMDS.___ABBR___={}
    if env.jit and env.jit.flush then
        e,msg=pcall(env.jit.flush)
        if not e then print(msg) end
    end
end

env.REOAD_SIGNAL=false
function env.reload()
    print("Reloading environment ...")
    env.unload()
    java.loader.ReloadNextTime=env.CURRENT_DB
    env.REOAD_SIGNAL=true
end

function env.exit()
    print("Exited.")
    env.unload()
    os.exit(true,true)
end

function env.load_data(file,isUnpack)
    if not file:find('[\\/]') then file=env.join_path(env.WORK_DIR,"data",file) end
    local f=io.open(file,file:match('%.dat$') and "rb" or "r")
    if not f then
        return {}
    end
    local txt=f:read("*a")
    f:close()
    if not txt or txt:gsub("[\n\t%s\r]+","")=="" then return {} end
    return isUnpack==false and txt or env.MessagePack.unpack(txt)
end

function env.save_data(file,txt)
    if not file:find('[\\/]') then file=env.join_path(env.WORK_DIR,"data",file) end
    local f=io.open(file,file:match('%.dat$') and "wb" or "w")
    if not f then
        env.raise("Unable to save "..file)
    end
    env.MessagePack.set_array("always_as_map")
    txt=env.MessagePack.pack(txt)
    f:write(txt)
    f:close()
end

function env.write_cache(file,txt)
    local dest=env._CACHE_PATH..file
    file=dest
    local f=io.open(file,'w')
    if not f then
        env.raise("Unable to save "..file)
    end
    f:write(txt)
    f:close()
    return dest
end

function env.resolve_file(filename,ext)
    if not filename:find('[\\/]') then
        filename= env.join_path(env._CACHE_PATH,filename)
    elseif not filename:find('^%a:') then
        filename= env.join_path(env.WORK_DIR,filename)
    end

    if ext and ext~="" then
        local exist_ext=filename:lower():match('%.([^%.\\/]+)$')
        local found=false
        if type(ext)=="table" then
            for _,v in ipairs(ext) do
                if v:lower()==exist_ext then
                    found=true
                    break
                end
            end
        else
            found=(exist_ext==ext:lower())
        end
        if not found then filename=filename..'.'..(type(ext)=="table" and ext[1] or ext) end
    end

    return filename
end

local title_list,CURRENT_TITLE={}

function env.set_title(title)
    local callee=env.callee():gsub("#%d+$","")
    title_list[callee]=title
    local titles=""
    if not env.module_list then return end
    for _,k in ipairs(env.module_list) do
        if (title_list[k] or "")~="" then
            if titles~="" then titles=titles.."    " end
            titles=titles..title_list[k]
        end
    end
    if not titles or titles=="" then titles="DBCLI - Disconnected" end
    if CURRENT_TITLE~=titles then
        CURRENT_TITLE=titles
        env.uv.set_process_title(titles)
    end
end

function env.reset_title()
    title_list={}
    env.set_title()
end

function env.ask(question,range,default)
    local isValid,desc,value=true,question
    if default then 
        desc=desc..' ['..tostring(default)..']' 
    elseif range then
        desc=desc..' ['..range..']'
    end
    --env.printer.write(desc..': ')
    env.IS_ASKING=question
    value,env.IS_ASKING=reader:readLine(env.space..desc..": "),nil
    value=value and value:trim() or ""

    value=value:gsub('\\([0-9]+)',function(x) return string.char(tonumber(x)) end)
    value=value:gsub('(0x[0-9a-f][0-9a-fA-F]?)',function(x) return string.char(tonumber(string.format("%d",x))) end)
   
    if value=="" then
        if default~=nil then return default end
        isValid=false
    elseif range and range ~='' then
        local lower,upper=range:match("([%-%+]?%d+)%s*%-%s*([%-%+]?%d+)")
        if lower then
            value,lower,upper=tonumber(value),tonumber(lower),tonumber(upper)
            if not value or not (value>=lower and value<=upper) then
                isValid=false
            end
        elseif range:find(",") then
            local match=0
            local v=value:lower()
            for k in range:gmatch('([^,%s]+)') do
                if v==k:lower() then
                    match=1
                end
            end
            if match==0 then
                isValid=false
            end
        elseif not value:match(range) then
            isValid=false
        end
    end

    if isValid then return value end
    return env.ask(question,range,default)
end

return env