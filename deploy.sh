#!/bin/bash
JAVA_OPTIONS="-Xmx2048m -Xms126m -XX:+HeapDumpOnOutOfMemoryError "
EXTEND_JAVA_OPTIONS=" -Dspring.config.location=../application.properties"
JARPATH=`pwd`
CONFIGFILE="application.properties"
JARNAMEWITHOUTVERSION=''
declare -a JARNAME

function findLast()
{
  group=$1
  if [[ ${#group[@]} == 0 ]]
  then
     echo "error"
  else
     target=''
     targetTimestamp=''
     for tmp in ${group[@]}
     do
      #  echo "tmp=${tmp}"
       tmpTimestamp=`echo ${tmp} | grep -E '[0-9]{14}$' -o`
       if [[ targetTimestamp == '' ]]
       then
           targetTimestamp="${tmpTimestamp}"
           target="${tmp}"
       else
           if [[ "${tmpTimestamp}" > "${targetTimestamp}" ]]
           then
              targetTimestamp="${tmpTimestamp}"
              target="${tmp}"
           fi
       fi
     done
     echo "${target}"
  fi
}

function findJAR()
{
  JARNAME=($(ls -l $JARPATH | grep \\.jar$ | awk '{print $NF}'))
  if [[ ${#JARNAME[@]} > 1 ]]
  then
    echo "[${JARNAME[@]}] too many jar files!!! I don't know startup which one."
    exit 1
  elif [[ ${#JARNAME[@]} == 0 ]]
  then
    echo "this is no jar file in $JARPATH"
    exit 1
  else
    version=`echo "${JARNAME[0]}" | grep -E '\-[0-9][\.0-9]+[-0-9a-zA-Z]*\.jar$' -o`
    # echo "version=${version}"
    JARNAMEWITHOUTVERSION=${JARNAME[0]/${version}/}
    # echo "JARNAMEWITHOUTVERSION=${JARNAMEWITHOUTVERSION}"
  fi
}

function rename()
{
  findJAR
  if [[ ${#JARNAME[@]} != 1 ]]
  then
    if [[ ${#JARNAME[@]} == 0 ]]
    then
       echo "there is no jar in current dir."
    else
       echo "[${JARNAME[@]}] too many jar files!!! I don't know which one should be renamed."
       exit 1
    fi
  else
    local timestamp=`date "+%Y%m%d%H%M%S"`
    mv "${JARNAME[0]}" "${JARNAME[0]}${timestamp}"
    echo "${JARNAME[0]} has been renamed to ${JARNAME[0]}${timestamp}"
  fi
}

function restore()
{
  declare -a jarfiles
  local jarfiles=`ls | grep -E '\-[0-9][\.0-9]+[-0-9a-zA-Z]*\.jar[0-9]{14}$'`
  # echo "${jarfiles}"
  local res_jar=$(findLast "${jarfiles}")
  # echo "res_jar=${res_jar}"
  if [[ "${res_jar}" == '' || "${res_jar}" == 'error' ]]
  then
    echo "there is no backup jar files."
  else
    if [[ -f "${JARNAME[0]}" ]] 
    then
      # 如果之前的文件存在，则重命令
      rename
    fi
    #需要获取jar名称
    local timestamp=`echo "${res_jar}" | grep -E '[0-9]{14}$' -o`
    mv "${res_jar}" "${res_jar/${timestamp}/}"
    echo "${res_jar} has been renamed as ${res_jar/${timestamp}/}."
  fi
}

function renameConfig()
{
    if [[ -f "${CONFIGFILE}" ]]; then
       local timestamp=`date "+%Y%m%d%H%M%S"`
       mv "${CONFIGFILE}" "${CONFIGFILE}${timestamp}"
       echo "${CONFIGFILE} has been renamed as ${CONFIGFILE}${timestamp}."
    else
       echo "there is no application.properties."
    fi
}

function restoreConfig()
{
  declare -a configfiles
  local configfiles=`ls | grep -E ^application.properties[0-9]\{14\}$`
  # echo "${configfiles}"
  local res=$(findLast "${configfiles}")
  # echo "${res}"
  if [[ "${res}" == '' || "${res}" == 'error' ]]
  then
    echo "there is no backup cofig files."
  else
    if [[ -f "${CONFIGFILE}" ]] 
    then
      # 如果之前的文件存在，则重命令
      renameConfig
    fi
    mv "${res}" "${CONFIGFILE}"
    echo "${res} has been renamed as ${CONFIGFILE}."
  fi
}

function unzipServer()
{
  local parentDir=`echo ${JARPATH} | awk -F '/' '{print $NF;}'`
  # echo "parentDir=${parentDir}"
  if [[ -f "${parentDir}.zip" ]]
  then
    #重命名配置文件
    renameConfig
    #获取jar包
    local jarfiles=(`ls -l | grep jar$ | awk '{print $NF}'`)
    #重命名jar包
    if [[ ${#jarfiles[@]} == 1 ]]
    then
       rename
    fi
    #解压
    unzip -o "${parentDir}.zip"
  else
    echo "there is no zip file named ${parentDir}.zip"
  fi
}

function start()
{
  findJAR
  # 根据服务名称来获取process id
  local server_pid=`ps -ef | grep java | grep " ${JARNAMEWITHOUTVERSION}" | awk '{print $2}'`
  if [ "${server_pid}" != "" ]
  then
     echo -e "${JARNAMEWITHOUTVERSION} is alived with pid ${server_pid}.\nabort start action"
     exit 1
  fi
  if [[ -f "${CONFIGFILE}" ]]
  then
     nohup java ${JAVA_OPTIONS} -jar ${JARNAME[0]} > /dev/null 2>&1 & 
  else
     nohup java ${JAVA_OPTIONS} ${EXTEND_JAVA_OPTIONS} -jar ${JARNAME[0]} > /dev/null 2>&1 &
  fi
  server_pid=`ps -ef | grep java | grep " ${JARNAME[0]}" | awk '{print $2}'`
  echo "${JARNAME[0]} is alived with pid ${server_pid}."
  return 0
}

#启动状态返回0 停止状态返回1
function status()
{
  findJAR
  local server_pid=`ps -ef | grep java | grep " ${JARNAMEWITHOUTVERSION}" | awk '{print $2}'`
  if [ "${server_pid}" != "" ]
  then
     echo -e "${JARNAME[0]} is alived with pid ${server_pid}."
     return 0
  else
     echo "${JARNAME[0]} isn't alived."
     return 1
  fi
}

function stop()
{
  findJAR
  local server_pid=`ps -ef | grep java | grep " ${JARNAMEWITHOUTVERSION}" | awk '{print $2}'`
  if [ "$server_pid" != "" ]
  then
     echo "${JARNAMEWITHOUTVERSION} is alived with pid ${server_pid}."
     kill -9 $server_pid
     echo "has stopped ${JARNAME[0]}"
     return 0
  else
     echo "${JARNAME[0]} isn't alived."
     return 1
  fi
}

function initNacosFile()
{
  local filename=$1
  echo "nacos.server-addr=172.16.0.127:8848" > ${filename}
  echo "nacos.namespace=" >> ${filename}
  echo "nacos.endpoint=" >> ${filename}
  echo "nacos.access-key=" >> ${filename}
  echo "nacos.secret-key=" >> ${filename}
}

function initNacos()
{
    local params=($*)
    if [[ ${#params[@]} -le 1 ]]
    then
       return 1
    fi
    unset params[0]
    local filename=${JARPATH}/../application.properties
    if [[ ! -f "${filename}" ]]
    then
        initNacosFile ${filename}
    fi    
    for p in ${params[@]}
    do
       local key=${p%%=*}
       local line=`grep -n "^${key}" ${filename} | cut -d ":" -f1`
       if [[ -z ${line} ]]
       then
          echo ${p} >> ${filename}
       else
          sed -i "s#${key}.*#${p}#g" ${filename}
       fi
    done
}

function usage(){
   echo -e "Usage:sh deploy.sh COMMAND \n\
   COMMAND OPTIONS:\n\
   start:start the server.\n\
   stop:stop the server.\n\
   restart:restart the server.\n\
   status:show the server pid.\n\
   rename:rename the jar with timestamp.\n\
   restore:rename the last backup jaryyyymmddHHMMSS to jar.\n\
   renameconfig:rename ${CONFIGFILE} with timestamp.\n\
   restoreconfig:rename the last backup ${CONFIGFILE}yyyymmddHHMMSS to ${CONFIGFILE}.\n\
   uncompress:unzip zip file in current dir. it will do the rename action and renameconfig first."
}

echo '------------------------start-------------------'

case "$1" in
   "start")
     start
   ;;
   "stop")
     stop
   ;;
   "restart")
     stop
     sleep 1
     start
   ;;
   "status")
     status
   ;;
   "rename")
     rename
   ;;
   "restore")
     restore
   ;;
   "renameconfig")
     renameConfig
   ;;
   "restoreconfig")
     restoreConfig
   ;;
   "uncompress")
     unzipServer
   ;;
   "initnacos")
      initNacos $*
   ;;
   *)
     usage
   ;;
  esac