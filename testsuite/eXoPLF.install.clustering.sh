#!/bin/bash -xv

CLU_NODE=${CLU_NODE:-"1"}
CLEANUP_DATA=${CLEANUP_DATA:-"false"}
startup_time_stamp=`date +%Y%m%d_%H%M%S`
function clearcache
{
	echo "`date` before drop cache mem usage info:"
	free -m
	echo "`date` going to clear file system cache"
    	sudo sync
    	sudo echo 3 | sudo tee /proc/sys/vm/drop_caches
	sysctl -w vm.drop_caches=3
	echo "`date` after dropping cache mem usage info:"
	free -m
	
}

# setup cluster on each node
function setup
{
  cp /mnt/jcrdata/testsuite/mysql-connector-java-5.1.21-bin.jar standalone/deployments/
  standalone_config=bin/standalone.conf
  EXO_QA_OPTS_EXISTS=`grep -c -E "(EXO_QA_CLUSTER_OPTS|EXO_QA_JVM_OPTS|EXO_QA_OPTS)" ${standalone_config}`
  if [ ! ${EXO_QA_OPTS_EXISTS} -gt 0 ]; then
    sed -i "s/JAVA_OPTS=\"\$JAVA_OPTS -Djboss.server.default.config=standalone-exo.xml\"/JAVA_OPTS=\"\$JAVA_OPTS -Djboss.server.default.config=standalone-exo-cluster-mysql.xml\"/g" ${standalone_config}
    sed -i "s/standalone-exo-cluster-mysql.xml\"/standalone-exo-cluster-mysql.xml\"\nJAVA_OPTS=\"\$JAVA_OPTS \$\{EXO_QA_OPTS\} \"/g" ${standalone_config}
    sed -i "s/standalone-exo-cluster-mysql.xml\"/standalone-exo-cluster-mysql.xml\"\nEXO_QA_OPTS=\$\{EXO_QA_OPTS:-\"\$\{EXO_QA_CLUSTER_OPTS\} \$\{EXO_QA_JVM_OPTS\}\"\}/g" ${standalone_config}
    sed -i "s/standalone-exo-cluster-mysql.xml\"/standalone-exo-cluster-mysql.xml\"\nEXO_QA_JVM_OPTS=\$\{EXO_QA_JVM_OPTS:-\"-XX:+HeapDumpOnOutOfMemoryError\"\}/g" ${standalone_config}
    sed -i "s#HeapDumpOnOutOfMemoryError#HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=./ -XX:MaxPermSize=512m #g" ${standalone_config}
    sed -i "s#standalone-exo-cluster-mysql.xml\"#standalone-exo-cluster-mysql.xml\"\nEXO_QA_CLUSTER_OPTS=\$\{EXO_QA_CLUSTER_OPTS:-\"-Djgroups.tcpping.initial_hosts\"\}#g" ${standalone_config}
    sed -i "s#jgroups.tcpping.initial_hosts#jgroups.tcpping.initial_hosts=192.168.3.41[7800],192.168.3.41[7800] -Djgroups.tcp.start_port=7800 -Djgroups.tcpping.num_initial_members=2  -Djboss.partition.name=192.168.3.42 -Djboss.node.name=node${CLU_NODE} -Djboss.server.data.dir=${SHARED_DATA_DIR}#g" ${standalone_config}
    

    if [ ! `grep -c "EXO_QA_OPTS" ${standalone_config}` -gt 0 ]; then
      echo "WARNING: setup step failed, exit!"
      exit
    fi
    
    # setup standalone/configuration/standalone-exo-cluster-mysql.xml
    exo_cluster_config_file=standalone/configuration/standalone-exo-cluster-mysql.xml
    cp standalone/configuration/standalone-exo-cluster.xml ${exo_cluster_config_file}
    # add ajp connector
    sed -i -r "s#(<connector name=\"http\"[^>]+/>)#\1\n<connector name=\"ajp\" protocol=\"AJP/1.3\" socket-binding=\"ajp\" scheme=\"http\"/>#g" ${exo_cluster_config_file}
    sed -i -r "s/( [pP]ort=\")/\1${CLU_NODE}/g" ${exo_cluster_config_file}
    
    sed -i -r "s#<driver>hsqldb-driver.jar</driver>#<!--\0-->#g" ${exo_cluster_config_file}
    sed -i -r "s#<driver-class>org.hsqldb.jdbcDriver</driver-class>#<!--\0-->#g" ${exo_cluster_config_file}
    sed -i -r "s#<connection-url>jdbc:hsqldb.*</connection-url>#<!--\0-->#g" ${exo_cluster_config_file}
    
    sed -i -r "s#(<connection-url>jdbc:hsqldb.*</connection-url>.*)#\1\n<driver>mysql-connector-java-5.1.21-bin.jar</driver><driver-class>com.mysql.jdbc.Driver</driver-class><connection-url>jdbc:mysql://${MYSQL_SERVER_ALIAS}:3306/plf?autoReconnect=true</connection-url>#g" ${exo_cluster_config_file}

    sed -i "s#<user-name>sa</user-name>#<user-name>exotest</user-name>#g" ${exo_cluster_config_file}
    sed -i "s#<password/>#<password>${MYSQL_PASSWD}</password>#g" ${exo_cluster_config_file}
    
    sed -i -r "s#<valid-connection-checker class-name=\"org.jboss.jca.adapters.jdbc.extensions.novendor.JDBC4ValidConnectionChecker\"/>#<!-- \0 --><exception-sorter class-name=\"org.jboss.jca.adapters.jdbc.extensions.mysql.MySQLExceptionSorter\" /><valid-connection-checker class-name=\"org.jboss.jca.adapters.jdbc.extensions.mysql.MySQLValidConnectionChecker\" />#g" ${exo_cluster_config_file}
    
             
    
  fi
}

# this function should work only with CLU_NODE=1
function load_dataset
{
  if [ -f "${DATASET_FILE}" ]; then
    echo " ${LOG_PREFIX_INFO} REMOVE GATEIN DATA AND DBs "
    echo " ${LOG_PREFIX_INFO} INIT DATASET  "
    if [ -d "${DATASET_TARGET_DIR}" ]; then
      rm -rf ${DATASET_TARGET_DIR}
    fi
    mkdir ${DATASET_TARGET_DIR};
    unzip ${DATASET_FILE} -d ${DATASET_TARGET_DIR};

    pushd ${DATASET_TARGET_DIR}/*
    DATASET_TARGET_DIR=`pwd`;
    popd
    
    
    echo " ${LOG_PREFIX_INFO}   remove gatein data "
    rm -rf standalone/data/*

    echo " ${LOG_PREFIX_INFO} RESTORE GATEIN DATA AND DBs "
    echo " ${LOG_PREFIX_INFO}   restore gatein data  "
    cp -R ${DATASET_TARGET_DIR}/data/* standalone/data/

      DATASET_DB_FILE=`ls ${DATASET_TARGET_DIR}/*.sql`
      echo " ${LOG_PREFIX_INFO} restoring databases to ${MYSQL_SERVER} from sql dump file: ${DATASET_DB_FILE} "
      mysql ${MYSQL_CONNECTION_PARAM}<${DATASET_DB_FILE}
  fi
}

MYSQL_DB=${MYSQL_DB:-"plf"}
MYSQL_PASSWD=${MYSQL_PASSWD:-"exodb"}
MYSQL_SERVER_ALIAS=${MYSQL_SERVER_ALIAS:-"fqa-cluster-mysql-db"}
START_UP_WAIT_TIME=${START_UP_WAIT_TIME:-"108000"};
MYSQL_CONNECTION_PARAM=${MYSQL_CONNECTION_PARAM:-" -uexotest -p${MYSQL_PASSWD} -h${MYSQL_SERVER_ALIAS}"}
mysqladmin ${MYSQL_CONNECTION_PARAM} flush-hosts
mysqladmin ${MYSQL_CONNECTION_PARAM} create ${MYSQL_DB}

MYSQL_SERVER=`mysqladmin ${MYSQL_CONNECTION_PARAM} variables | grep hostname | awk -F \| ' { print $3 } ' | sed 's| ||g'`
if [[ -z $MYSQL_SERVER || "!$MYSQL_SERVER" == "!" ]]; then
  echo "`date`,!!!WARNING: can not connect to the mysql server with MYSQL_CONNECTION_PARAM=$MYSQL_CONNECTION_PARAM"
  exit
fi
DATASET_TARGET_DIR=DATASET
LOG_FILE=logs/catalina.out.${JMETER_SCRIPT_NAME}
export CATALINA_OUT=${LOG_FILE}
LOG_PREFIX_INFO="[INFO]: "
LOG_PREFIX_WARNING="[WARNING]: "
SERVER_STARTUP_NOTIFICATION="Server startup in"


#### ++ READ CONFIG FOR APPLICATION FROM APPLICATION_PARAMS
unset WORKING_DIR ; export WORKING_DIR=""
unset DATASET_FILE ; export DATASET_FILE=""
unset DATASET_JCR_DB_NAME ; export DATASET_JCR_DB_NAME=""
unset DATASET_IDM_DB_NAME ; export DATASET_IDM_DB_NAME=""
WORKING_DIR=`echo ${APPLICATION_PARAMS} | awk '{ print $1}'`;
DATASET_FILE=`echo ${APPLICATION_PARAMS} | awk '{ print $2}'`;
SHARED_DATA_DIR=`echo ${APPLICATION_PARAMS} | awk '{ print $3}'`;
echo "WORKING_DIR=${WORKING_DIR}"
echo "DATASET_FILE=${DATASET_FILE}"
echo "DATASET_JCR_DB_NAME=${DATASET_JCR_DB_NAME}"
echo "DATASET_IDM_DB_NAME=${DATASET_IDM_DB_NAME}"
echo " ${LOG_PREFIX_INFO} unset JAVA_OPTS"
unset JAVA_OPTS


ORIGINAL_DIR=`pwd`
echo "pushd "${WORKING_DIR}": $PWD/${WORKING_DIR}"
ls -lsa ${WORKING_DIR}
pushd ${WORKING_DIR}/
iscontinue=$?
if [ $iscontinue -eq 0 ]; then
	# detect which package to start
	PLF_STARTUP_COMMAND="./start_eXo.sh"
	if [[ -f ./bin/standalone.sh && -f ./bin/standalone.conf ]]; then
	    if [[ -f ./bin/bootstrap.jar && -f ./start_eXo.sh ]]; then
		    PLF_STARTUP_COMMAND="./start_eXo.sh"
	    else
		echo "#!/bin/bash">./start_eXo.sh
		echo "pushd bin">>./start_eXo.sh
		echo "bash ./standalone.sh -b 0.0.0.0">>./start_eXo.sh
		chmod +x ./start_eXo.sh
		SERVER_STARTUP_NOTIFICATION="Controller Boot Thread.*JBAS.*JBoss EAP.*started.*in"
		LOG_FILE="./standalone/log/server.log"
		mkdir -p ./logs
		ln -s ${LOG_FILE} ./logs
	    fi
	fi
	
	# clear file system cache
	clearcache
	# setup PLF configuration
	setup
	CURRENT_DIR=`pwd`;
	# create shared path if it does not exist
	if [ ! -d ${SHARED_DATA_DIR} ]; then
	  mkdir -p ${SHARED_DATA_DIR}
	  chmod 777 -R ${SHARED_DATA_DIR}
	fi
	
	# link shared folder
	if [ -d standalone/data ]; then
	  echo "WARNING: the data folder existing will be moved to standalone/old_data_${startup_time_stamp} "
	  mv standalone/data standalone/old_data_${startup_time_stamp}
	fi
	
	if [ -f standalone/data ]; then
	  if [ ! "`readlink -f standalone/data`" == "`readlink -f ${SHARED_DATA_DIR}`" ]; then
	    echo "WARNING: the data folder link existing will be moved to standalone/old_data_${startup_time_stamp} "
	    mv standalone/data standalone/old_data_${startup_time_stamp}
	  fi
	else
	  # create link
	  ln -s ${SHARED_DATA_DIR} standalone/data
	fi
	
	echo " ${LOG_PREFIX_INFO}   remove temp/* folder  "
	rm -rf temp/*
	rm -rf standalone/tmp/*
	jcr_local_swap_data_path="standalone/tmp/jcr_swap"
	jcr_local_swap_data_real_path="standalone/data/gatein/jcr/"
	mkdir -p ${jcr_local_swap_data_path}
	

	
	if [ ${CLU_NODE} -eq 1 ]; then
	  if [ "${CLEANUP_DATA}" == "true" ]; then
	    echo "WARNING: going to cleanup gatein data first"
	    rm -rf standalone/data/*
	    mysqladmin -f ${MYSQL_CONNECTION_PARAM} drop ${MYSQL_DB}
	    mysqladmin ${MYSQL_CONNECTION_PARAM} create ${MYSQL_DB}
	  fi
	  load_dataset
	fi
	
	echo "${LOG_PREFIX_INFO} remove ${jcr_local_swap_data_real_path}/swap, then create "
	rm -rf ${jcr_local_swap_data_real_path}/swap
	mkdir -p ${jcr_local_swap_data_real_path}
	ln -s ${WORKING_DIR}/${jcr_local_swap_data_path} ${jcr_local_swap_data_real_path}/swap

	echo " ${LOG_PREFIX_INFO} backup logs"
	backup_dir="backup_`date +%Y%m%d_%H%M`"
	mkdir gatein/logs/${backup_dir}
	mv gatein/logs/*.* gatein/logs/${backup_dir}
	bzip2 gatein/logs/${backup_dir}/*log
	gzip gatein/logs/${backup_dir}/catalina.out*
	
	mkdir logs/${backup_dir}
	mv logs/*.* logs/${backup_dir}
	bzip2 logs/${backup_dir}/*log
	gzip logs/${backup_dir}/catalina.out*

	mkdir standalone/log/${backup_dir}
	mv standalone/log/*.* standalone/log/${backup_dir}
	bzip2 standalone/log/${backup_dir}/*log
	gzip standalone/log/${backup_dir}/catalina.out*


	echo " ${LOG_PREFIX_INFO} STARTUP  "
	echo "Start the PLF with command: ${PLF_STARTUP_COMMAND}"
	mkdir -p ./logs
	nohup ./${PLF_STARTUP_COMMAND}  &
	PLF_PID=$!

	wait_time_for_logfile=0;
	while [ true ]; do
	  if [ ! -f ${LOG_FILE} ]; then
	    if [ $wait_time_for_logfile -le 120 ]; then
	      wait_time_for_logfile=$(( $wait_time_for_logfile + 1 ))
	      echo " ${LOG_PREFIX_INFO} Still wating for ${LOG_FILE} to exists ... "
	      sleep 1;
	    else
	      echo " ${LOG_PREFIX_INFO} FAILED to load the application as ${LOG_FILE} does not appear after $wait_time_for_logfile seconds"
	      exit;
	      break;
	    fi
	  else
	    break;
	  fi
	done
	echo " ${LOG_PREFIX_INFO} Wating for the application to startup by looking into the file `readlink -f ${LOG_FILE}`"

	for i in `eval echo {1..${START_UP_WAIT_TIME}}`; do
	    tail -150 ${LOG_FILE} | grep -E "${SERVER_STARTUP_NOTIFICATION}" >>/dev/null

	    if [ $? = "0" ]; then
		START_ERROR=false
		echo "The application started after $i seconds, follow its log file"
		echo " -------------- APPLICATION STARTUP INFO ------------------------"
		cat  ${LOG_FILE}
		break;
	    fi
	    sleep 1
	    
	done
	
	sleep 5
	echo " -------------- APPLICATION PROCESS INFO ------------------------"
	ps aux | grep java | grep "${WORKING_DIR}">${ORIGINAL_DIR}/${TESTPLAN}_process.info
	cat ${ORIGINAL_DIR}/${TESTPLAN}_process.info
fi
