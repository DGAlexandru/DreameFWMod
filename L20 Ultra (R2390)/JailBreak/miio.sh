#!/bin/sh
source /usr/bin/config

MIOT_LOG=/tmp/log/miio_client.log
MIAT_LOG=/tmp/log/miio_agent.log

if [ "${BOARD_TYPE}" == "MR112" ]; then
    LOG_MAX_SIZE=1048576
else
    LOG_MAX_SIZE=2097152
fi

function miio_ready_check()
{
    if [ ! -f "${DEVICE_CONF_FILE}" ]; then
        exit 0
    fi

    if [ "${MIIO_SDK_MJAC}" == "true" ]; then
        MIIO_STR1=`grep "mjac_i2c" ${DEVICE_CONF_FILE} | cut -d '=' -f 2`
        MIIO_STR2=`grep "mjac_gpio" ${DEVICE_CONF_FILE} | cut -d '=' -f 2`
    else
        MIIO_STR1=`grep "did=" ${DEVICE_CONF_FILE} | cut -d '=' -f 2`
        MIIO_STR2=`grep "key=" ${DEVICE_CONF_FILE} | cut -d '=' -f 2`
    fi

    for i in `seq 1 10`
    do
        MAC_STR=`ifconfig -a | grep ${WIFI_NODE} | awk '{print $5}'`
        if [ -n "${MAC_STR}" ]; then
            break
        else
            sleep 0.5
        fi
    done

    if [ -z "${MIIO_STR1}" -o -z "${MIIO_STR2}" -o -z "${MAC_STR}" ]; then
        exit 0
    fi
}

function do_start()
{
    # 设置miio_client启动参数配置
    if [ "${MIIO_SDK_MJAC}" == "true" ]; then       # 米家安全芯片，使用 -oMSC，默认开启kv存储功能
        MIOT_CONF=" -D -d/etc/miio/ -oMSC"
    elif [ "${MIIO_AUTO_OTA}" == "true" ]; then     # 支持自动OTA升级，必须启动kv存储功能
        MIOT_CONF=" -D -d/etc/miio/"
    elif [ "${MIIO_KV_STORE}" == "false" ]; then    # 需要关闭kv存储(不支持自动OTA时有效)，使用 -oDISABLE_PSM
        MIOT_CONF=" -D -d/etc/miio/ -oDISABLE_PSM"
    else                                            # 默认开启kv存储功能
        MIOT_CONF=" -D -d/etc/miio/"
    fi

    # 设置miio_agent启动参数配置
    MIAT_CONF=" -D"

    # 设置miio_client日志参数
    if [ -f "${DEBUG_VERSION_FILE}" ]; then
        backup_log_file ${MIAT_LOG} ${LOG_MAX_SIZE} yes
        MIOT_CONF="${MIOT_CONF} -l0 -s1024 -L${MIOT_LOG}"
        MIAT_CONF="${MIAT_CONF} -l4 -L${MIAT_LOG}"
    else
        MIOT_CONF="${MIOT_CONF} -l0"
        MIAT_CONF="${MIAT_CONF} -l0"
    fi

    # kill miio sdk
    killall -9 miio_client_helper_nomqtt.sh > /dev/null 2>&1
    killall -9 miio_client miio_recv_line > /dev/null 2>&1
    rm -f /tmp/miio_unix_* > /dev/null 2>&1

    log "start miio_client miio_client_helper_nomqtt.sh"
    miio_client ${MIOT_CONF} > /dev/null 2>&1
    miio_client_helper_nomqtt.sh > /dev/null 2>&1 &

    [ $(which miio_agent) ] && {
        log "start miio_agent";
        killall -9 miio_agent > /dev/null 2>&1;
        sleep 1;
        miio_agent ${MIAT_CONF} > /dev/null 2>&1;
    } &

    if [ "$1" == "rm_mark" ]; then
        (sleep 2 && rm -f ${RESTART_MIIO}) &
    fi
}

function do_stop()
{
    killall -9 miio_monitor.sh > /dev/null 2>&1
    touch ${RESTART_MIIO}

    log "stop miio_client_helper_nomqtt.sh miio_client miio_recv_line"
    killall -9 miio_client_helper_nomqtt.sh
    killall -9 miio_client miio_recv_line
    [ $(which miio_agent) ] && killall -9 miio_agent
    rm -f /tmp/miio_unix_* > /dev/null 2>&1
}

miio_ready_check

case "$1" in
    start)
        do_start "rm_mark"
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_stop
        sleep 1
        do_start
        ;;
    *)
        do_start
        ;;
esac

log "$0 load !!!!"
exit 0

awk '{if ($1 > 60) exit 1}' /proc/uptime && true || exit 1

echo [`cat /proc/uptime | cut -d " " -f 1`] $0 execute success!!!!!! | tee /dev/ttyS0 -a /tmp/log/sysinit.log > /dev/null 2>&1
