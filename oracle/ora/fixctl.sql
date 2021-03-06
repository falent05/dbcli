/*[[Query optimizer fixed controls. Usage: @@NAME {[keyword] [sid] [inst_id]} [-f"filter"]
   --[[
       @CHECK_ACCESS_CTL: gv$session_fix_control={gv$session_fix_control}, default={(select userenv('instance') inst_id, a.* from v$session_fix_control a)}
       &FILTER: default={1=1}, f={}
   --]]
]]*/
select * from &CHECK_ACCESS_CTL
where ((:V1 IS NULL and optimizer_feature_enable=(select value from v$parameter where name='optimizer_features_enable'))
  or   (:V1 IS NOT NULL and instr(lower(BUGNO||DESCRIPTION),lower(:V1))>0))
AND    inst_id=nvl(:V3,userenv('instance'))
and    session_id=nvl(:V2,userenv('sid')) 
AND    &filter
order by 1