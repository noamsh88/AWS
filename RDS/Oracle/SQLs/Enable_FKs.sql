set linesize 120
set pagesize 0
set verify off
set feedback off

spool XXX_enable.sql
select 'set feedback on' from dual;
select 'set echo on' from dual;

select
	'alter table '||table_name||' enable constraint '||constraint_name||';'
from
	user_constraints
where
	constraint_type in ('R')
;

--select ' @$HOME/SCRIPTS/TOOLS/check_cons_status'  from dual;

spool off

spool XXX_enable.log

set echo on

@XXX_enable

spool off

exit;
