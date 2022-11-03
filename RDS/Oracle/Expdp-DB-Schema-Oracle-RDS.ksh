#!/bin/ksh
set -evx
export DB_USER=$1
export DB_PASS=${DB_USER}
export DB_INST=$2
###########################################################################################################################
# Script Actions:
# 1. takes export(Data Pump) of Oracle RDS schema
# 2. Copy Dump and log file from DPDIR->S3 Bucket-> Unix Account
# Assumptions:
# AWS CLI installed on unix account
###########################################################################################################################
export DATE=`date +%Y%m%d_%H%M%S`
export SCRIPT_DIR=`pwd`
export CONF_FILE=${SCRIPT_DIR}/Expdp-DB-Schema-Oracle-RDS.par
. ${CONF_FILE}
export LOG_DIR=${SCRIPT_DIR}/Logs
export DUMP_DIR=${SCRIPT_DIR}/Dumps

Init_Validation()
{
  if [[ -z ${DB_USER} || -z ${DB_PASS} || -z ${DB_INST} ]]
  then
    echo
    echo "USAGE : `basename $0` <DB_USER> <DB_INST>"
    echo -e "\nExample: `basename $0` VFDDB7 ABPXORA \n "
    exit 1
  fi

  # Validate $CONF_FILE parameters values are set
  if [[ -z ${ORACLE_HOME} || -z ${ORA_PASS} || -z ${S3_BUCKET_NAME} ]]
  then
    echo "Please Validate all parameters values are set on ${CONF_FILE} "
    echo "Exiting.."
    exit 1
  fi

  # Validate connectivity to oracle(admin user) before Export
  echo "exit" | sqlplus -L oracle/${ORA_PASS}@${DB_INST} | grep Connected
  if [[ ! $? -eq 0 ]]; then
   echo "Please Check Connectivity to oracle@${DB_INST}"
   exit 1
 fi

}

Exp_DB_Schema()
{
  export DUMP_NAME=Expdp_${DB_USER}_${DB_INST}_${DATE}.dmp
  export LOG_NAME=Expdp_${DB_USER}_${DB_INST}_${DATE}.log

  echo "
DECLARE
 H1   NUMBER;
BEGIN
    H1 := DBMS_DATAPUMP.OPEN (OPERATION => 'EXPORT', JOB_MODE => 'SCHEMA', JOB_NAME => '${DB_USER}1', VERSION => 'COMPATIBLE');
    DBMS_DATAPUMP.SET_PARALLEL(HANDLE => H1, DEGREE => 5);
    DBMS_DATAPUMP.ADD_FILE(HANDLE => H1, FILENAME => '${LOG_NAME}', DIRECTORY => 'DATA_PUMP_DIR', FILETYPE => 3);
    DBMS_DATAPUMP.SET_PARAMETER(HANDLE => H1, NAME => 'KEEP_MASTER', VALUE => 0);
    DBMS_DATAPUMP.METADATA_FILTER(HANDLE => H1, NAME => 'SCHEMA_EXPR', VALUE => 'IN(''${DB_USER}'')');
    DBMS_DATAPUMP.SET_PARAMETER(HANDLE => H1, NAME => 'ESTIMATE', VALUE => 'BLOCKS');
    DBMS_DATAPUMP.ADD_FILE(HANDLE => H1, FILENAME => '${DUMP_NAME}', DIRECTORY => 'DATA_PUMP_DIR', FILETYPE => 1);
    DBMS_DATAPUMP.SET_PARAMETER(HANDLE => H1, NAME => 'INCLUDE_METADATA', VALUE => 1);
    DBMS_DATAPUMP.SET_PARAMETER(HANDLE => H1, NAME => 'DATA_ACCESS_METHOD', VALUE => 'AUTOMATIC');
    DBMS_DATAPUMP.START_JOB(HANDLE => H1, SKIP_CURRENT => 0, ABORT_STEP => 0);
END;
/
  " | ${ORACLE_HOME}/bin/sqlplus oracle/${ORA_PASS}@${DB_INST}

  # Wait that dump and log files will be synced on AWS level
  sleep 180

}


Check_Exp_Log()
{
  # Copy log from DPDIR to ${SCRIPT_DIR}
  ${SCRIPT_DIR}/Oracle_RDS_Copy_File_DPDIR_to_Unix.ksh  ${LOG_NAME} ${DB_INST}

  if [ $? -eq 1 ]
  then
   echo "Failed to Copy ${LOG_NAME} File From DPDIR/S3 to Unix Account"
   echo "Exiting.."
   exit 1
  fi

  mv ${LOG_NAME} ${LOG_DIR}

  grep "ORA-" ${LOG_DIR}/${LOG_NAME}

  if [ $? -eq 0 ]
  then
          echo "ERROR: Errors During export of ${DB_USER}@${DB_INST}"
          echo "Please check log file for more details: ${LOG_DIR}/${LOG_NAME}"
          echo "Exiting..."
          exit 1
  else
          echo "########################################################################"
          echo "Export of ${DB_USER}@${DB_INST} Schema Finished Successfully."
          echo "########################################################################"
  fi

}

Copy_Dump_DPDIR_to_Unix()
{
  sleep 60
  ${SCRIPT_DIR}/Oracle_RDS_Copy_File_DPDIR_to_Unix.ksh  ${DUMP_NAME} ${DB_INST}

  if [ $? -eq 1 ]
  then
   echo "Failed to Copy ${DUMP_NAME} File From DPDIR/S3 to Unix Account"
   echo "Exiting.."
   exit 1
  fi

  mv ${DUMP_NAME} ${DUMP_DIR}
  gzip ${DUMP_DIR}/${DUMP_NAME}
  echo "Gzip Dump File Location: ${DUMP_DIR}/${DUMP_NAME}.gz"

}


### Main ###
Init_Validation
Exp_DB_Schema
Check_Exp_Log
Copy_Dump_DPDIR_to_Unix
