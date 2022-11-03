#!/bin/ksh -xv
export FILE_PATH=$1
export DB_INST=$2

###########################################################################################################################
# Scripts Actions:
# 1. Copy File from Unix its Unix location to S3 Bucket
# 2. Copy File from S3 to Oracle RDS DPDIR
# Assumptions:
# AWS CLI installed on unix account
###########################################################################################################################
export FILE_NAME=$(basename "$FILE_PATH")
export SCRIPT_DIR=`pwd`
export CONF_FILE=${SCRIPT_DIR}/Oracle-RDS-Copy-File-DPDIR-to-Unix.par
. ${CONF_FILE}

Init_Validation()
{
  if [[ -z ${FILE_PATH} || -z ${DB_INST}  ]]
  then
    echo
    echo "USAGE : `basename $0` <FILE_PATH> <DB_INST> "
    echo -e "\nExample: `basename $0` /var/SP/users/abptgr/SCRIPTS/AWS/tst.log ABPXORA\n "
    exit 1
  fi

  #Validate $CONF_FILE parameters values are set
  if [[ -z ${ORACLE_HOME} || -z ${ORA_PASS} || -z ${S3_BUCKET_NAME}  ]]
  then
    echo "Please Validate all parameters values are set on ${CONF_FILE} "
    echo "Exiting.."
    exit 1
  fi

}

Copy_File_Unix_to_S3()
{
  aws s3 cp ${FILE_PATH} s3://${S3_BUCKET_NAME}

  sleep 10

  # Validate if file copied to S3 Bucket
  aws s3 ls s3://${S3_BUCKET_NAME}/${FILE_NAME}

  if [[ $? -ne 0 ]]; then
    echo "Copy Failed, File does not exist on ${S3_BUCKET_NAME} S3 Bucket"
    echo "Exiting.."
    exit 1
  fi

  echo "${FILE_PATH} Copied Succesfully to ${S3_BUCKET_NAME}"
}

Copy_File_S3_to_DPDIR()
{

  echo "
  SELECT rdsadmin.rdsadmin_s3_tasks.download_from_s3(
        p_bucket_name => '${S3_BUCKET_NAME}',
        p_s3_prefix => '${FILE_NAME}',
        p_directory_name => 'DATA_PUMP_DIR')
        AS TASK_ID FROM DUAL;
  " | ${ORACLE_HOME}/bin/sqlplus oracle/${ORA_PASS}@${DB_INST}

  sleep 10

  IS_COPIED=`
  echo "
  set head off
  SELECT count(*)
  FROM TABLE(rdsadmin.rds_file_util.listdir('DATA_PUMP_DIR'))
  WHERE FILENAME='${FILE_NAME}';
  " | ${ORACLE_HOME}/bin/sqlplus -s oracle/${ORA_PASS}@${DB_INST}
  `

  IS_COPIED=`echo ${IS_COPIED} | tr -d ' ' | tr -d 't'`

  if [[ ${IS_COPIED} -eq 1 ]]
  then
    echo "${FILE_NAME} Copied Succesfully From S3 Bucket ${S3_BUCKET_NAME} to DPDIR"
  else
    echo "Failed to Copy ${FILE_NAME} From S3 Bucket ${S3_BUCKET_NAME} to DPDIR"
    echo "Exiting.."
    exit 1
  fi

}

###Main###
Init_Validation
Copy_File_Unix_to_S3
Copy_File_S3_to_DPDIR
