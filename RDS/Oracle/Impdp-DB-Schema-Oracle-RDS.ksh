#!/bin/ksh
set -exv
export TRG_USER=$1
export TRG_PASS=${TRG_USER}
export TRG_INST=$2
export DUMP_PATH=$3
export SRC_SCHEMA=$4
export BACKUP=$5
###########################################################################################################################
# Script Actions:
# 1. Backup Target DB Schema (if BACKUP=Y)
# 2. Copy Dump to S3 Bucket and DPDIR of $TRG_INST
# 3. Disable FKs and Triggers on Target DB
# 4. Import Dump to Target DB (Truncate Mode)
# 5. Enable FKs and Triggers on Target DB
# 6. Check Import Log
# Assumptions:
# AWS CLI installed on unix account
###########################################################################################################################
export DATE=`date +%Y%m%d_%H%M%S`
export SCRIPT_DIR=`pwd`
export CONF_FILE=${SCRIPT_DIR}/Impdp-DB-Schema-Oracle-RDS.par
. ${CONF_FILE}
export LOG_DIR=${SCRIPT_DIR}/Logs
export DUMP_DIR=${SCRIPT_DIR}/Dumps
export SQL_DIR=${SCRIPT_DIR}/SQLs
###########################################################################################################################

Init_Validation()
{
  if [[ -z ${TRG_USER} || -z ${TRG_PASS} || -z ${TRG_INST} || -z ${DUMP_PATH} || -z ${SRC_SCHEMA} || -z ${BACKUP} ]]
  then
    echo
    echo "USAGE : `basename $0` <TRG_USER> <TRG_INST> <DUMP_PATH> <SRC_SCHEMA> <BACKUP Y/N>"
    echo -e "\nExample: ./`basename $0` VFDREFO8 ABPXORA /var/SP/users/abptgr/SCRIPTS/AWS/Dumps/MST2000_VFDABP1_REF_V2000_P90.dmp  MST2000 Y \n "
    exit 1
  fi

  BACKUP=`echo "${BACKUP}" | tr -s  '[:lower:]' '[:upper:]'`
  if [[ ${BACKUP} -ne "Y" || ${BACKUP} -ne "N" ]]
  then
    echo "Please Enter Correct Value (Y/N) For BACKUP Variable"
    exit 1
  fi

  #Validate $CONF_FILE parameters values are set
  if [[ -z ${ORACLE_HOME} || -z ${ORA_PASS} || -z ${S3_BUCKET_NAME} ]]
  then
    echo "Please Validate all parameters values are set on ${CONF_FILE}"
    echo "Exiting.."
    exit 1
  fi

  #Validate if ORACLE_HOME exists
  if [[ ! -e ${ORACLE_HOME} ]]
  then
    echo "Oracle Home: ${ORACLE_HOME} Not Found , Please set its correct path on ${CONF_FILE}"
    exit 1
  fi

  #Validate connectivity to oracle(admin user) before Import
  echo "exit" | sqlplus -L oracle/${ORA_PASS}@${TRG_INST} | grep Connected
  if [[ ! $? -eq 0 ]]; then
   echo "Please Check Connectivity to oracle@${TRG_INST}"
   exit 1
  fi

  #Validate if Export Script Exist in ${SCRIPT_DIR}
  if [[ ! -e ${SCRIPT_DIR}/Expdp-DB-Schema-Oracle-RDS.ksh ]]
  then
   echo "${SCRIPT_DIR}/Expdp-DB-Schema-Oracle-RDS.ksh not found at ${SCRIPT_DIR} directory"
   echo "Exiting.."
   exit 1
  fi

  #Validate if Copy Script from Unix to S3 and Oracle RDS DPDIR Exist in ${SCRIPT_DIR}
  if [[ ! -e ${SCRIPT_DIR}/Oracle-RDS-Copy-File-Unix-to-DPDIR.ksh ]]
  then
   echo "${SCRIPT_DIR}/Oracle-RDS-Copy-File-Unix-to-DPDIR.ksh not found at ${SCRIPT_DIR} directory"
   echo "Exiting.."
   exit 1
  fi

  #Validate if Copy Script from DPDIR to Unix Exist in ${SCRIPT_DIR}
  if [[ ! -e ${SCRIPT_DIR}/Oracle_RDS_Copy_File_DPDIR_to_Unix.ksh ]]
  then
   echo "${SCRIPT_DIR}/Oracle-RDS-Copy-File-Unix-to-DPDIR.ksh not found at ${SCRIPT_DIR} directory"
   echo "Exiting.."
   exit 1
  fi

  #Validate Disable/Enable FKs and Triggers SQLs are on  ${SQL_DIR} directory
  if [[ ! -e ${SQL_DIR}/Disable_FKs.sql || ! -e ${SQL_DIR}/Enable_FKs.sql || ! -e ${SQL_DIR}/Disable_Triggers.sql || ! -e ${SQL_DIR}/Enable_Triggers.sql ]]
  then
   echo "Please Validate all following required SQL files exist under ${SCRIPT_DIR}/SQLs directory"
   echo "Disable_FKs.sql"
   echo "Enable_FKs.sql"
   echo "Disable_Triggers.sql"
   echo "Enable_Triggers.sql"
   echo "Exiting..."
   exit 1
  fi
}

Backup_Target_DB_Schema()
{
  if [[ "${BACKUP}" == "N" ]]
  then
    echo "BACKUP Variable Value is set to N"
    echo "Skipping Backup Part.."
    return 0
  fi

  ${SCRIPT_DIR}/Expdp-DB-Schema-Oracle-RDS.ksh ${TRG_USER} ${TRG_INST}

  if [ $? -eq 1 ]
  then
   echo "Failed to Backup Target DB ${TRG_USER}@${TRG_INST}"
   echo "Please check Logs under ${SCRIPT_DIR}/Logs"
   echo "Exiting.."
   exit 1
  fi

}


Copy_Dump_to_DPDIR()
{
  ${SCRIPT_DIR}/Oracle-RDS-Copy-File-Unix-to-DPDIR.ksh ${DUMP_PATH} ${TRG_INST}

  if [ $? -eq 1 ]
  then
   echo "Failed to Copy ${DUMP_PATH} to DPDIR of ${TRG_INST}"
   echo "Exiting.."
   exit 1
  fi

}

Check_Constraints()
{
  export CK_FK=`
  echo "
  set head off
  SELECT DISTINCT status FROM user_constraints where constraint_type in ('R');
  " | ${ORACLE_HOME}/bin/sqlplus -s ${TRG_USER}/${TRG_PASS}@${TRG_INST}`

  export CK_FK=`echo ${CK_FK} | tr -d ' ' | tr -d 't'`

}


Check_Triggers()
{
  export CK_TRIG=`
  echo "
  set head off
  SELECT DISTINCT status FROM user_triggers;
  " | ${ORACLE_HOME}/bin/sqlplus -s ${TRG_USER}/${TRG_PASS}@${TRG_INST}`

  export CK_TRIG=`echo ${CK_TRIG} | tr -d ' ' | tr -d 't'`

}


Disable_FKs()
{
  ${ORACLE_HOME}/bin/sqlplus ${TRG_USER}/${TRG_PASS}@${TRG_INST}  @${SQL_DIR}/Disable_FKs.sql

  #Validate all FKs Disabled
  Check_Constraints

  if [[ ${CK_FK} -eq "DISABLED" ]]
  then
    echo "ALL FKs Disabled Succesfully ${TRG_USER}@${TRG_INST}"
  else
    echo "Not ALL FKs Disabled Succesfully on ${TRG_USER}@${TRG_INST}"
    echo "Exiting.."
    exit 1
  fi

}


Disable_Triggers()
{
  #Validate if DB Schema has triggers
  export COUNT_TRIG=`
  echo "
  set head off
  SELECT count(*) status FROM user_triggers;
  " | ${ORACLE_HOME}/bin/sqlplus -s ${TRG_USER}/${TRG_PASS}@${TRG_INST}`

  export COUNT_TRIG=`echo ${COUNT_TRIG} | tr -d ' ' | tr -d 't'`

  if [[ ${COUNT_TRIG} -eq 0 ]]
  then
    echo "No Triggers Found on ${TRG_USER}@${TRG_INST}, Skipping.."
    return 0
  fi

  ${ORACLE_HOME}/bin/sqlplus ${TRG_USER}/${TRG_PASS}@${TRG_INST}  @${SQL_DIR}/Disable_Triggers.sql

  #Validate all FKs Disabled
  Check_Triggers

  if [[ ${CK_TRIG} -eq "DISABLED" ]]
  then
    echo "ALL Triggers Disabled Succesfully ${TRG_USER}@${TRG_INST}"
  else
    echo "Not ALL Triggers Disabled Succesfully on ${TRG_USER}@${TRG_INST}"
    echo "Exiting.."
    exit 1
  fi

}


Import_Dump()
{
  export DUMP_NAME=$(basename "$DUMP_PATH")
  export LOG_NAME=Impdp_${TRG_USER}_${TRG_INST}_${DATE}.log

  echo "
  SET SERVEROUTPUT ON
  DECLARE
    H1 NUMBER;               -- DATA PUMP JOB HANDLE
    V_SRC_SCH_EXP VARCHAR2(30);
  BEGIN
    H1 := DBMS_DATAPUMP.OPEN(OPERATION => 'IMPORT', JOB_MODE => 'TABLE', JOB_NAME=>NULL);
    V_SRC_SCH_EXP := 'IN(''${TRG_USER}'')';
    DBMS_DATAPUMP.ADD_FILE(HANDLE => H1, FILENAME =>'${DUMP_NAME}', DIRECTORY =>'DATA_PUMP_DIR');
    DBMS_DATAPUMP.ADD_FILE(HANDLE => H1, FILENAME => '${LOG_NAME}', DIRECTORY => 'DATA_PUMP_DIR', FILETYPE => DBMS_DATAPUMP.KU\$_FILE_TYPE_LOG_FILE);
    DBMS_DATAPUMP.SET_PARAMETER(HANDLE => H1, NAME => 'TABLE_EXISTS_ACTION', VALUE => 'TRUNCATE');
    DBMS_DATAPUMP.SET_PARAMETER(HANDLE => H1, NAME => 'INCLUDE_METADATA', VALUE => 0);
    DBMS_DATAPUMP.METADATA_REMAP(H1,'REMAP_SCHEMA','${SRC_SCHEMA}','${TRG_USER}');
    begin
              DBMS_DATAPUMP.START_JOB(H1);
    end;
  END;
  /
  " | ${ORACLE_HOME}/bin/sqlplus oracle/${ORA_PASS}@${TRG_INST}

  sleep 180

}



Enable_FKs()
{
  ${ORACLE_HOME}/bin/sqlplus ${TRG_USER}/${TRG_PASS}@${TRG_INST}  @${SQL_DIR}/Enable_FKs.sql

  #Validate all FKs Disabled
  Check_Constraints

  if [[ ${CK_FK} -eq "ENABLED" ]]
  then
    echo "ALL FKs Enabled Succesfully ${TRG_USER}@${TRG_INST}"
  else
    echo "Not ALL FKs Enabled Succesfully on ${TRG_USER}@${TRG_INST}"
    echo "Exiting.."
    exit 1
  fi

  rm -fr ${SCRIPT_DIR}/XXX_*.log  ${SCRIPT_DIR}/XXX_*.sql

}


Enable_Triggers()
{
  #Validate if DB Schema has triggers
  export COUNT_TRIG=`
  echo "
  set head off
  SELECT count(*) FROM user_triggers;
  " | ${ORACLE_HOME}/bin/sqlplus -s ${TRG_USER}/${TRG_PASS}@${TRG_INST}`

  export COUNT_TRIG=`echo ${COUNT_TRIG} | tr -d ' ' | tr -d 't'`

  if [[ ${COUNT_TRIG} -eq 0 ]]
  then
    echo "No Triggers Found on ${TRG_USER}@${TRG_INST}, Skipping.."
    return 0
  fi

  ${ORACLE_HOME}/bin/sqlplus ${TRG_USER}/${TRG_PASS}@${TRG_INST}  @${SQL_DIR}/Enable_Triggers.sql

  #Validate all FKs Disabled
  Check_Triggers

  if [[ ${CK_TRIG} -eq "ENABLED" ]]
  then
    echo "ALL Triggers Disabled Succesfully ${TRG_USER}@${TRG_INST}"
  else
    echo "Not ALL Triggers Disabled Succesfully on ${TRG_USER}@${TRG_INST}"
    echo "Exiting.."
    exit 1
  fi

  rm -fr ${SCRIPT_DIR}/TTT_*.log  ${SCRIPT_DIR}/TTT_*.sql

}


Check_Import_Log()
{
  #Copy Import log from DPDIR -> S3 Bucket -> ${SCRIPT_DIR}
  ${SCRIPT_DIR}/Oracle_RDS_Copy_File_DPDIR_to_Unix.ksh ${LOG_NAME} ${TRG_INST}

  if [ $? -eq 1 ]
  then
   echo "Failed to Copy Log ${LOG_NAME} from DPDIR to ${SCRIPT_DIR}"
   echo "Exiting.."
   exit 1
  fi

  mv ${SCRIPT_DIR}/${LOG_NAME}  ${SCRIPT_DIR}/Logs/${LOG_NAME}

  grep -i ora- ${SCRIPT_DIR}/Logs/${LOG_NAME}

  if [ $? -eq 0 ]
  then
          echo "ERROR: Errors During Import to ${TRG_USER}@${TRG_INST}"
          echo "Please check log file for more details: ${SCRIPT_DIR}/Logs/${LOG_NAME}"
          echo "Exiting..."
          exit 1
  else
          echo "########################################################################"
          echo "Import of ${DUMP_NAME} to ${TRG_USER}@${TRG_INST} Schema Finished Successfully."
  fi

}


###Main###
Init_Validation
Backup_Target_DB_Schema
Copy_Dump_to_DPDIR
Disable_FKs
Disable_Triggers
Import_Dump
Enable_FKs
Enable_Triggers
Check_Import_Log
