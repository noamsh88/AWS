set linesize 120
set pagesize 0
set verify off
set feedback off

spool TTT_enable.sql
select 'set feedback on' from dual;
select 'set echo on' from dual;

select
        'alter trigger '|| trigger_name ||' enable ;'
from
        user_triggers
;

spool off

spool TTT_enable.log

@TTT_enable

spool off
exit
