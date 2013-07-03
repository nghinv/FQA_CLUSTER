#!/bin/bash
  export testplan=$2;#"KS_WIKI_BENCH_005"
  export stageresultfile=${testplan}_testresult.log;
  export stageresultfile_upload=${testplan}_upload_testresult.log;
  export application_process_info=${testplan}_process.info;
  export testplan_original_config="${testplan}_ORIGINAL_CONFIG"
  export testplan_current_config="${testplan}_CURRENT_CONFIG"
  export testplan_current_testconfig="${testplan}_CURRENT_TESTCONFIG"
  export testplan_current_upload_queue="${testplan}_CURRENT_UPLOAD"
  export testplan_upload_queue="${testplan}_UPLOAD_QUEUE"
  export testplan_upload_info="${testplan}_UPLOAD_INFO"
  export testplan_upload_info_tmp="${testplan}_UPLOAD_INFO_TMP"
  export last_status="0";
  export SUCCESS_STATE="success"
  export FAILURE_STATE="failure"
  export LONES="process_identification"
  export ORIGINAL_DIR=`pwd`
  export firstline=""
  export CLEANUP_DATA=${CLEANUP_DATA:-"false"}  

  export APPLICATION_PARAMS=""
  export INJECTOR_PARAMS=""
  export CONTROLLER_PARAMS=""
  export JMETER_SLEEP_TIME_BEFORE_STOPPING=120;
  export TESTPLAN=$testplan
  export IS_JPROFILING_ON=""
  export APPLICATION_HOST=""
  export APPLICATION_PORT=""
  export APPLICATION_PATH=""
  export APPLICATION_REMOTE_PORT=${TARGET_JMX_PORT:-"8004"}
  export JMETER_SCRIPT_NAME=""
  export JMETER_TEST_DURATION=""
  export JPROFILER_DETAIL=""
  export APPLICATION_KILL_SIGNAL=""
  export JMETER_TEST_GROUP_ID=""

  

  echo "--== remove test result file ==--"
  rm -rf ${stageresultfile}
  echo "--== create empty test result file ==--"
  touch ${stageresultfile}
  chmod 777 ${stageresultfile}
  
function system_infomation
{
  # disk information
  echo " ---------------------------------- SYSTEM INFORMATION ---------------------------------- "
  echo "`date` INFO:: Disk free information"
  df -h
  # memfree
  echo "`date` INFO:: Memory free information"
  free -m
  # users
  echo "`date` INFO:: users login"
  users
  # uptime
  echo "`date` INFO:: uptime"
  uptime
  echo " -----------------------------------------------------------------------------------------"
}

# reload config from testplan_original_config to testplan_current_config
function reloadconfig
{
  echo " ++ reloadconfig ${testplan_original_config} > ${testplan_current_config}"
  reloadconfig_timestamp=`date +%F"_"%T`
  mkdir -p backup/${testplan}/${reloadconfig_timestamp}
  echo " backup ${testplan_original_config} ${testplan_current_config} ${testplan_current_upload_queue} ${testplan_upload_queue} to backup/${testplan}/${reloadconfig_timestamp}"
  cp ${testplan_original_config} ${testplan_current_config} ${testplan_current_upload_queue} ${testplan_upload_queue} backup/${testplan}/${reloadconfig_timestamp}
  # reset testplan_current_config
  cat ${testplan_original_config}>${testplan_current_config}
  
  # reset testplan_current_testconfig
  echo "">${testplan_current_testconfig}
  echo "">${testplan_current_upload_queue}
  echo "">${testplan_upload_queue}
  enable_readwrite_mode_for_config_file
  echo " -- reloadconfig"
}

output_to_report()
{
  echo $1
  echo "$1">>${testplan_upload_info}
}

exit_upload()
{
  if [ ${last_status} -eq "0" ]; then
    echo ${SUCCESS_STATE}>${stageresultfile_upload};
  else
    echo ${FAILURE_STATE}>${stageresultfile_upload};
  fi
  exit
}

function enable_readwrite_mode_for_config_file
{
  echo " ++ enable_readwrite_mode_for_config_file"
  chmod 777 ${testplan_current_testconfig}
  chmod 777 ${testplan_current_config}
  echo " -- enable_readwrite_mode_for_config_file"
}
#load first line from testplan_current_config, save to testplan_current_testconfig
function loadfirstconfigline_to_testplan_current_testconfig
{
    firstline=""
    echo " ++ loadfirstconfigline_to_testplan_current_testconfig";
    firstline=`egrep ^.*$ ${testplan_current_config} -m 1 -o`;
    echo "firstline=${firstline}, RESET_CODE=${RESET_CODE}"
    if [[ "x${firstline}" == "x" && "${RESET_CODE}" == "REWIND" ]]; then
      reloadconfig
      firstline=`egrep ^.*$ ${testplan_current_config} -m 1 -o`;
      if [[ "x${firstline}" == "x" || -z ${firstline} ]]; then
	firstline="false"
      fi
    fi
    echo ${firstline}>${testplan_current_testconfig};
    echo " -- loadfirstconfigline_to_testplan_current_testconfig = [${firstline}] "
    if [[ "${firstline}" == "false" || "x${firstline}" == "x" || -z ${firstline} ]]; then
      last_status="1"
    else
      last_status="0"
    fi
    echo "last_status=${last_status}"
}

# load from testplan_current_testconfig, export to variables by awk '{ print $# }'
function load_testplan_current_testconfig
{
    echo " ++ load_testplan_current_testconfig";
    APPLICATION_PARAMS=`cat ${testplan_current_testconfig} | awk -F ! '{ print $1}' `;
    CLEANUP_DATA_FLAG=`cat ${testplan_current_testconfig} | awk -F ! '{ print $2}' `;
    echo "INFO:: CLEANUP_DATA_FLAG=${CLEANUP_DATA_FLAG}"
    if [ "${CLEANUP_DATA_FLAG}" == "CLEANUP_DATA" ]; then
	CLEANUP_DATA="true";
    	echo "INFO:: CLEANUP_DATA=${CLEANUP_DATA}"
    fi
    CONTROLLER_PARAMS=`cat ${testplan_current_testconfig} | awk -F ! '{ print $3}' `;
    echo " -- load_testplan_current_testconfig"
}


function stop_application_deployment
{
  stop_a_process
}

function stop_a_process
{
  for i in $LONES; do
    echo " looking for processes with name contains [$i] "
    JPID=`ps aux | grep java | grep $i | awk '{print $2}'`
    if [ ! -z "$JPID" ]; then
      echo "detected lone $i (pid $JPID), killing it"
      kill -9 $JPID
    else
	echo "found no process with name contain [$i]"
    fi
  done
}

function trimfirstline
{
  echo " ++ trimfirstline"
  sed -i  -e '1,1d' ${testplan_current_config} 
  enable_readwrite_mode_for_config_file
  echo " -- trimfirstline"
}

system_infomation

unset STAGE
export STAGE=$1
unset RESET_CODE
RESET_CODE=$3
echo "STAGE=${STAGE}, RESET_CODE=${RESET_CODE}"
if [ "${RESET_CODE}" == "RESET" ]; then
  reloadconfig
fi

# delete first line in current config if it is empty
sed -i '/^[ \t]*$/d' ${testplan_current_config}
sed -i '/^[ \t]*$/d' ${testplan_current_config}
sed -i '/^[ \t]*$/d' ${testplan_current_config}

if [ "${STAGE}" == "START" ]; then
  loadfirstconfigline_to_testplan_current_testconfig
  echo "last_status=${last_status}"

  if [ ${last_status} -eq "0" ]; then
    load_testplan_current_testconfig
    STARTUP_SCRIPT=`echo ${CONTROLLER_PARAMS} | awk '{ print $1}'`;
    echo "CONTROLLER_PARAMS=${CONTROLLER_PARAMS}"
    bash ./${STARTUP_SCRIPT}
    if [ "${IS_JPROFILING_ON}" == "true" ]; then
      echo " ... ++ starting JProfiler features ++ ... "
      #start_jprofiler_features
      stop_all_jprofiling_features
      echo " ... -- starting JProfiler features -- ... "
    fi
    echo ${SUCCESS_STATE}>${stageresultfile};
  else
    echo ${FAILURE_STATE}>${stageresultfile};
  fi
fi


if [ "${STAGE}" == "STOP_APPLICATION" ]; then
    load_testplan_current_testconfig
    ${ORIGINAL_DIR}/${TESTSCRIPT}_jmxtrans_stop.sh
    sleep 5
    LONES="catalina.base=/java/exo-working Dexo.conf.dir.name jmxtrans program.name=run.sh /usr/lib/libreoffice/program/soffice.bin /opt/openoffice.org3/program/soffice.bin jboss.home.dir=/java/exo-working start_eXo.sh platform-clustering-util";
    stop_application_deployment
    echo ${SUCCESS_STATE}>${stageresultfile};
fi

if [ "${STAGE}" == "COUNT_DOWN_TEST" ]; then
  loadfirstconfigline_to_testplan_current_testconfig
  if [ ${last_status} -eq "0" ]; then
    load_testplan_current_testconfig
    trimfirstline
    echo ${SUCCESS_STATE}>${stageresultfile};
  else
    echo ${FAILURE_STATE}>${stageresultfile};
  fi
fi
