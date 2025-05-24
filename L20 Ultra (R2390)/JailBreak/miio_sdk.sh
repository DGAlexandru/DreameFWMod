#!/bin/sh
#
# Date: 2021.01
# Version: 0.0.1
#
#set -x

source /usr/bin/config

do_start() {
    /etc/rc.d/miio.sh
}

do_stop() {
    touch ${RESTART_MIIO} && sync
    /etc/rc.d/miio.sh stop
    sleep 0.1
    killall -9 wifi_start.sh > /dev/null 2>&1
    sleep 0.1
    killall -9 wifi_setup.sh > /dev/null 2>&1
    rm -f ${MIIO_TOKEN_FILE} && sync
}

do_restart() {
    avacmd iot '{"type":"iot", "notify":"close_server"}'
    sleep 0.2

    # stop miio processes
    /etc/rc.d/miio.sh stop
    sleep 0.1

    # must remove device.token wifi.conf device.uid when reset miio
    rm -f ${MIIO_TOKEN_FILE} ${WIFI_CONF_FILE} ${MIIO_UID_FILE} > /dev/null 2>&1
    # clean some miio configuration files
    rm -f ${MIIO_CONFIG_DB_FILE} > /dev/null 2>&1
    # remove device.country, otherwise config net from oversea to cn，it will still set oversea
    rm -f ${MIIO_COUNTRY_FILE} > /dev/null 2>&1
    sync
    sleep 0.1

    # start miio processes
    /etc/rc.d/miio.sh start

    sleep 0.2
    avacmd iot '{"type":"iot", "notify":"open_server"}'
}

do_check_netcfg() {
    if [ ! -f ${WIFI_CONF_FILE} ]; then
        touch ${FACTORY_AP_FILE}
    else
        rm -f ${FACTORY_AP_FILE}
    fi
}

case "$1" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_restart
        ;;
    check_netcfg)
        do_check_netcfg
        ;;
    *)
        log "$0 parameter error"
        ;;
esac
