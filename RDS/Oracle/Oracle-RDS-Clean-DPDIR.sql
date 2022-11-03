set lines 300 pages 200
set head off
spool Clean_Current_DPDIR_Files.sql

SELECT 'EXEC UTL_FILE.FREMOVE(' || '''DATA_PUMP_DIR''' || ',' || '''' || FILENAME || ''');'
FROM TABLE(rdsadmin.rds_file_util.listdir('DATA_PUMP_DIR'))
WHERE FILENAME LIKE 'Expdp_%'
ORDER BY FILENAME;

spool off


set echo on feed on
set feedback on
spool Clean_Current_DPDIR_Files.log
set define off

@Clean_Current_DPDIR_Files.sql

exit;

--To delete files in the DATA_PUMP_DIR that you no longer require, use the following command.
--SELECT * FROM TABLE(rdsadmin.rds_file_util.listdir('DATA_PUMP_DIR')) ORDER BY MTIME;
--EXEC UTL_FILE.FREMOVE('DATA_PUMP_DIR','<file name>');
