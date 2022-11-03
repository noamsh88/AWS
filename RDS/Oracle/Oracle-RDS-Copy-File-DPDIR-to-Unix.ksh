#!/bin/ksh
set -exv
export FILE_NAME=$1
export DB_INST=$2
###########################################################################################################################
# Scripts Actions:
# 1. Copy File from DPDIR(AWS Oracle RDS) S3 Bucket
# 2. Copy File from S3 to local unix (TRG_DIR)
# Assumptions:
# AWS CLI installed on unix account
###########################################################################################################################
export SCRIPT_DIR=`pwd`
export CONF_FILE=${SCRIPT_DIR}/Oracle-RDS-Copy-File-DPDIR-to-Unix.par
. ${CONF_FILE}

Init_Validation()
{
  if [[ -z ${FILE_NAME} || -z ${DB_INST} || -z ${TRG_DIR} ]]
  then
    echo
    echo "USAGE : `basename $0` <FILE_NAME> <DB_INST> <TRG_DIR>"
    echo -e "\nExample: `basename $0` Expdp_VFDDB7_ABPXORA_20210421_110853.log ABPXORA\n "
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


Copy_File_DPDIR_to_S3()
{
  echo "
  SELECT rdsadmin.rdsadmin_s3_tasks.upload_to_s3(
        p_bucket_name    =>  '${S3_BUCKET_NAME}',
        p_prefix         =>  '${FILE_NAME}',
        p_s3_prefix      =>  '',
        p_directory_name =>  'DATA_PUMP_DIR')
  AS TASK_ID FROM DUAL;
  "  | ${ORACLE_HOME}/bin/sqlplus oracle/${ORA_PASS}@${DB_INST}

}


Copy_File_S3_to_Unix()
{
  #wait that sync between DPDIR to S3 will be done
  sleep 120

  aws s3 cp s3://${S3_BUCKET_NAME}/${FILE_NAME} ${TRG_DIR}

  #Validate if file copied to TRG_DIR
  if [[ ! -e ${TRG_DIR}/${FILE_NAME} ]];then
    echo "Failed to Copy ${FILE_NAME} File From S3 Bucket ${S3_BUCKET_NAME}"
    exit 1
  fi

  #Validate file cksum
  CKSUM1=`cksum ${TRG_DIR}/${FILE_NAME} | awk '{print $2}'`

  if [[ ${CKSUM1} -eq 0 ]];then
    echo "${FILE_NAME} File Didn't Copied Succesfully, ${FILE_NAME} cksum is 0"
    echo "Exiting.."
    exit 1
  fi

  echo "${FILE_NAME} Copied Succesfully to ${TRG_DIR}"
}

###Main###
Init_Validation
Copy_File_DPDIR_to_S3
Copy_File_S3_to_Unix
