#!/bin/sh
#
# set -x

source /usr/bin/config disable_log

MIIO_CLIENT_LOG=/tmp/log/miio_client.log
MIIO_AGENT_LOG=/tmp/log/miio_agent.log
LOG_MAX_SIZE=1048576

[ $(which iot) ] && exit 0

if [ "${BOARD_TYPE}" != "MR112" ]; then
    DATA_CAPACITY=`df -m | awk '/\/data/{printf $2}'`
    if [ ${DATA_CAPACITY} -ge 256 ]; then
        LOG_MAX_SIZE=5242880
    fi
fi

backup_log_file ${MIIO_CLIENT_LOG} ${LOG_MAX_SIZE}
backup_log_file ${MIIO_AGENT_LOG} ${LOG_MAX_SIZE}

uptime | grep -q 'up 0 min'
[ $? -eq 0 ] && exit 0

if [ ! -f ${DEVICE_CONF_FILE} -o -f ${RESTART_MIIO} ]; then
    exit 0
fi

if [ "$MIIO_SDK_MJAC" == "true" ]; then
    MIIO_STR1=`grep "mjac_i2c" ${DEVICE_CONF_FILE} | cut -d '=' -f 2`
    MIIO_STR2=`grep "mjac_gpio" ${DEVICE_CONF_FILE} | cut -d '=' -f 2`
else
    MIIO_STR1=`grep "did=" ${DEVICE_CONF_FILE} | cut -d '=' -f 2`
    MIIO_STR2=`grep "key=" ${DEVICE_CONF_FILE} | cut -d '=' -f 2`
fi

if [ -z "${MIIO_STR1}" -o -z "${MIIO_STR2}" ]; then
    exit 0
fi

MIIO_CLIENT_PID=`pidof -o %PPID miio_client`
if [ -n "${MIIO_AGENT_BIN}" ]; then
    MIIO_AGENT_PID=`pidof -o %PPID miio_agent`
else
    MIIO_AGENT_PID="needn't check"
fi
if [ -e /usr/bin/miio_client_helper_mjac.sh ]; then
    MIIO_HELPER_PID=`pidof -o %PPID miio_client_helper_mjac.sh`
else
    MIIO_HELPER_PID=`pidof -o %PPID miio_client_helper_nomqtt.sh`
fi

if [ -z "${MIIO_HELPER_PID}" -o -z "${MIIO_CLIENT_PID}" -o -z "${MIIO_AGENT_PID}" ]
then
    if [ -z "${MIIO_CLIENT_PID}" ]; then
        /etc/rc.d/mi_tracking.sh "report" "system_fault" "{\"fault_type\":\"MIOT SDK process crashes\"}" &
    fi

    sleep 5
    log "MIIO HELPER=${MIIO_HELPER_PID} CLIENT=${MIIO_CLIENT_PID} AGENT=${MIIO_AGENT_PID}, restart miio"
    avacmd iot '{"type":"iot", "notify":"close_server"}' &
    /etc/rc.d/miio.sh
    sleep 1
    avacmd iot '{"type":"iot", "notify":"open_server"}' &
fi

awk '{if ($1 > 60) exit 1}' /proc/uptime && true || exit 1

echo [`cat /proc/uptime | cut -d " " -f 1`] $0 execute success!!!!!! | tee /dev/ttyS0 -a /tmp/log/sysinit.log > /dev/null 2>&1
