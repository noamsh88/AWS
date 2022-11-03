set linesize 120
set pagesize 0
set verify off
set feedback off

spool XXX_disable.sql

select 'set echo on ' from dual;
select 'set feedback on' from dual;

select
	'alter table '||table_name||' disable constraint '||constraint_name||';'
from
	user_constraints
where
	constraint_type in ('R')
;

spool off

spool XXX_disable.log

@XXX_disable

spool off

exit;
