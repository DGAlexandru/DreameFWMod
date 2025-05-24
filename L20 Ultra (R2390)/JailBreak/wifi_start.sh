#!/bin/sh
#
# Date: 2021.08
# Version: 4.3.2_0.0.1
#
# set -x

source /usr/bin/config

GATEWAY=192.168.5.1
NETMASK=255.255.255.0
IGNORE_SSID=0
[ "${TUYA_IOT_FLAG}" == "true" ] && GATEWAY=192.168.176.1

LOG_FILE=/data/log/wifi.log
WPA_SUPPLICANT_SCRIPT=/etc/init.d/wpa_supplicant.sh
WPA_SUPPLICANT_CONFIG_FILE=${WPA_CONF_FILE}
mkdir -p /data/config/wifi

if [ -z "${CHANNEL}" ]; then
    CHANNEL=6
fi

# 支持畅快连一键配网时，设置为1；否则设置为0
if [ "${MIIO_SDK_MJAC}" == "true" ]; then
    MIIO_NET_AUTO_PROVISION=0       # 使用安全芯片的产品，不支持一键配网功能
elif [ "${MIIO_AUTO_PROVISION}" == "yes" ]; then
    MIIO_NET_AUTO_PROVISION=1       # 非安全芯片的产品，配置支持一键配网功能
else
    MIIO_NET_AUTO_PROVISION=0       # 非安全芯片的产品，配置不支持一键配网功能
fi
if [ "${MIIO_SMART_CONFIG}" == "false" ]; then
    MIIO_NET_SMART_CONFIG=0
else
    MIIO_NET_SMART_CONFIG=1         # 支持畅快连改密同步时，设置为1；否则设置为0
fi

if [ $MIIO_NET_AUTO_PROVISION -eq 1 ]; then
    if [ x"${AP_IF_NAME}" = x ]; then
        ap_interface=wlan1
    else
        ap_interface=${AP_IF_NAME}
    fi
else
    if [ x"${AP_IF_NAME}" = x ]; then
        ap_interface=${WIFI_NODE}
    else
        ap_interface=${AP_IF_NAME}
    fi
fi
sta_interface=${WIFI_NODE}

get_bind_status() {
    if [ -f ${WIFI_CONF_FILE} ]; then
        bind_status="ok"
    else
        bind_status=""
    fi

    log "bind_status: $bind_status"
}

update_wpa_conf_apsta()
{
    cat <<EOF > $WPA_SUPPLICANT_CONFIG_FILE
ctrl_interface=/var/run/wpa_supplicant
update_config=1
network={
    key_mgmt=WPA-PSK WPA-PSK-SHA256 SAE
    ieee80211w=1
    scan_ssid=1
}
EOF
}

hidden_update()
{
    ssid=$1
    bssid=$2

    cat <<EOF > $WPA_SUPPLICANT_CONFIG_FILE
ctrl_interface=/var/run/wpa_supplicant
update_config=1
network={
    ssid="$ssid"
    bssid=$bssid
    key_mgmt=NONE
    scan_ssid=1
}
EOF
}

hidden_insert()
{
    ssid=$1
    bssid=$2

    cat <<EOF >> $WPA_SUPPLICANT_CONFIG_FILE

network={
    ssid="$ssid"
    bssid=$bssid
    key_mgmt=NONE
    scan_ssid=1
}
EOF
}

master_update()
{
    ssid=$1
    passwd_b64=$2

    hex_ssid=`echo -n "$ssid" | xxd -p -c 32`

    if [ x"$passwd_b64" = x ]; then
    cat <<EOF > $WPA_SUPPLICANT_CONFIG_FILE
ctrl_interface=/var/run/wpa_supplicant
update_config=1
network={
    ssid=$hex_ssid
    key_mgmt=NONE
    scan_ssid=1
}
EOF
    else
        if [ "${MIIO_SDK_MJAC}" == "true" ]; then
            key_mgmt="WPA-PSK"
            payload4="proto=WPA WPA2"
            passwd_final=`sed -n '/^psk=/p' ${WIFI_CONF_FILE}`
            passwd_final=${passwd_final#*psk=}
            if [ ${#passwd_final} -ge 66 ]; then
                passwd_final=${passwd_final#*\"}
                passwd_final=${passwd_final%\"*}
            fi
            cat <<EOF > $WPA_SUPPLICANT_CONFIG_FILE
ctrl_interface=/var/run/wpa_supplicant
update_config=1
network={
    ssid=$hex_ssid
    psk=$passwd_final
    key_mgmt=$key_mgmt
    $payload4
    scan_ssid=1
}
EOF
        else
            key_mgmt="WPA-PSK WPA-PSK-SHA256 SAE"
            payload4="ieee80211w=1"
            passwd_final="$(echo -n $passwd_b64 | base64 -d)"
            cat <<EOF > $WPA_SUPPLICANT_CONFIG_FILE
ctrl_interface=/var/run/wpa_supplicant
update_config=1
network={
    ssid=$hex_ssid
    psk="$passwd_final"
    key_mgmt=$key_mgmt
    $payload4
    scan_ssid=1
}
EOF
        fi
    fi
}

master_insert()
{
    ssid=$1
    passwd_b64=$2
    hex_ssid=`echo -n "$ssid" | xxd -p -c 32`

    if [ x"$passwd_b64" = x ]; then

    cat <<EOF >> $WPA_SUPPLICANT_CONFIG_FILE

network={
    ssid=$hex_ssid
    key_mgmt=NONE
    scan_ssid=1
}
EOF
    else
        if [ "${MIIO_SDK_MJAC}" == "true" ]; then
            key_mgmt="WPA-PSK"
            payload4="proto=WPA WPA2"
            passwd_final=`sed -n '/^psk=/p' ${WIFI_CONF_FILE}`
            passwd_final=${passwd_final#*psk=}
            if [ ${#passwd_final} -ge 66 ]; then
                passwd_final=${passwd_final#*\"}
                passwd_final=${passwd_final%\"*}
            fi
            cat <<EOF >> $WPA_SUPPLICANT_CONFIG_FILE
network={
    ssid=$hex_ssid
    psk=$passwd_final
    key_mgmt=$key_mgmt
    $payload4
    scan_ssid=1
}
EOF
        else
            key_mgmt="WPA-PSK WPA-PSK-SHA256 SAE"
            payload4="ieee80211w=1"
            passwd_final="$(echo -n $passwd_b64 | base64 -d)"
            cat <<EOF >> $WPA_SUPPLICANT_CONFIG_FILE
network={
    ssid=$hex_ssid
    psk="$passwd_final"
    key_mgmt=$key_mgmt
    $payload4
    scan_ssid=1
}
EOF
        fi
    fi
}

update_wpa_conf_select_hidden()
{
    hide_ssid=$1
    hide_bssid=$2

    get_master_network
    log "miio_ssid:$miio_ssid"
    log "miio_passwd:$miio_passwd"
    log "miio_ssid_5g:$miio_ssid_5g"
    log "miio_passwd_5g:$miio_passwd_5g"

    get_bind_status

    if [ x"$bind_status" != x"ok" ]; then
        hidden_update "$hide_ssid" "$hide_bssid"
    else
        hidden_update "$hide_ssid" "$hide_bssid"
        if [ x"$miio_ssid" != x ]; then
            master_insert "$miio_ssid" "$passwd_b64"
        fi
        if [ x"$miio_ssid_5g" != x ]; then
            master_insert "$miio_ssid_5g" "$miio_passwd_5g"
        fi
    fi
}

update_wpa_conf_select_master()
{
    miio_ssid=$1
    passwd_b64=$2
    miio_ssid_5g=$3
    miio_passwd_5g=$4
    net_added=0

    if [ x"$miio_ssid_5g" != x ]; then
        master_update "$miio_ssid_5g" "$miio_passwd_5g"
        net_added=1
    fi

    if [ x"$miio_ssid" != x ]; then
        if [ "${MIIO_SDK_MJAC}" == "true" ]; then
            if [ $net_added -eq 0 ]; then
                master_update "$miio_ssid" "$passwd_b64"
            else
                master_insert "$miio_ssid" "$passwd_b64"
            fi
        else
            if [ $net_added -eq 0 ]; then
                master_update "$miio_ssid" "$passwd_b64"
            else
                master_insert "$miio_ssid" "$passwd_b64"
            fi
            # ssid_b64=`echo -n "${miio_ssid}" | base64`
            # if [ -n "${passwd_b64}" ]; then
            #     if [ -f ${NA_RELEASE} ]; then
            #         sed -i '/^#pwd_b64/d' ${WIFI_CONF_FILE}
            #     fi
            # else
            #     passwd_b64=`echo -n "${miio_passwd}" | base64 | sed ':lable;N;s/\n//g;b lable'`
            # fi
            # flock -xn /var/run/manager_ap.lock -c "manager_ap.sh add_ap ${ssid_b64} ${passwd_b64} base64"
        fi
    fi
}

get_mac()
{
    macstring=

    mac1=`echo ${macstring} | cut -d ':' -f 5`
    mac2=`echo ${macstring} | cut -d ':' -f 6`
    MAC=${mac1}${mac2}

    log "MAC is $MAC"
}

get_ssid()
{
    macstring=`ifconfig ${ap_interface} | grep HWaddr | awk '{print $NF}'`
    MAC_STR=`echo ${macstring} | awk -F ':' '{print $5$6}'`

    if [ "${TUYA_IOT_FLAG}" == "true" ] || [ "${NC_TYPE}" == "3" ]; then
        AP_PREFIX=$(jshon -F /var/run/runava.conf -e AP_PREFIX -u 2>/dev/null)
        [ -z "${AP_PREFIX}" ] && AP_PREFIX=SmartLife
        SSID_NAME="${AP_PREFIX}-${MAC_STR}"
    else
        if [ "${NC_TYPE}" == "2" ]; then
            DEVICE_CONF_FILE=/data/config/dmio/device.conf
        fi
        MODEL_STR=`grep "model=" ${DEVICE_CONF_FILE} | cut -d '=' -f 2 | sed 's/\./-/g'`

        SSID_NAME="${MODEL_STR}_miap${MAC_STR}"
    fi

    log "get ssid:$SSID_NAME"
}

get_ip()
{
    # start udhcpc, forbid running udhcpc.sh in the background
    killall -9 udhcpc 2>/dev/null
    flock -x /var/run/udhcpc.lock -c "/usr/bin/udhcpc.sh $sta_interface"

    # check if we've got ip
    ip=`wpa_cli status | grep ip_address | cut -d '=' -f 2`
    log "get ip addr: $ip"

    echo 3 > /proc/sys/kernel/printk
}

wifi_ap_mode()
{
    log "SET wifi AP mode"
    echo `date` "start ${ap_interface} AP mode" >> ${LOG_FILE}

    if [ -f ${CONFIGNET_FLAG} ]; then
        avacmd msg_cvt '{"type":"msgCvt", "wifi":{"state":"ap"}}' &
    fi

    # stop wifi relative application
    killall -9 udhcpc wpa_supplicant hostapd dnsmasq

    # restart wifi driver
    /usr/bin/wifi_act.sh rmmod
    sleep 0.5
    /etc/init.d/wifi.sh

    # clear ip address
    ipaddr flush $sta_interface
    ipaddr flush $ap_interface

    ifconfig $sta_interface down
    ifconfig $ap_interface down

    # open ap
    ifconfig $ap_interface up
    ifconfig $ap_interface ${GATEWAY} netmask ${NETMASK}

    # start hostapd
    get_ssid
    sed -e "s/AP_IF_NAME/${ap_interface}/" -e "s/SSID_NAME/${SSID_NAME}/" -e "s/CHANNEL/${CHANNEL}/" -e "s/IGNORE_SSID/${IGNORE_SSID}/" /etc/wifi/hostapd.conf > /tmp/hostapd_${ap_interface}.conf
    mkdir -p /var/run/hostapd
    hostapd /tmp/hostapd_${ap_interface}.conf -B

    # sed dnsmasq configure file use ap interface
    if [ ! -f ${WIFI_START_WLAN1} ] || [ "${USE_WIFI_BASE_STATION}" != "true" ]; then
        sed "s/AP_IF_NAME/${ap_interface}/" /etc/wifi/dnsmasq.conf > /tmp/dnsmasq.conf
        if [ "${GATEWAY}" != "192.168.5.1" ]; then
            GATEWAY_HEAD=${GATEWAY%.*}
            sed -i "s/192.168.5/${GATEWAY_HEAD}/g" /tmp/dnsmasq.conf
        fi
        echo -n "" > /tmp/dnsmasq.leases
        dnsmasq -C /tmp/dnsmasq.conf -x /tmp/dnsmasq.pid
    fi

    # notify other process network ap state
    /usr/bin/network_hook.sh ap

    log "finish AP mode"
    echo `date` "finish ${ap_interface} AP ssid=${SSID_NAME}" >> ${LOG_FILE}
}

wifi_close_sta_mode()
{
    log "Close wifi STA mode"

    killall -9 udhcpc wpa_supplicant
    ifconfig $sta_interface down
    ipaddr flush $sta_interface
}

wifi_sta_mode()
{
    log "SET wifi STA mode"
    echo `date` "start ${sta_interface} STA mode" >> ${LOG_FILE}

    # stop wifi relative application
    killall -9 udhcpc wpa_supplicant hostapd dnsmasq

    # restart wifi driver
    /usr/bin/wifi_act.sh rmmod
    sleep 0.5
    /etc/init.d/wifi.sh

    # open sta
    update_wpa_conf_apsta

    # clear ip address
    ipaddr flush $sta_interface
    ifconfig $sta_interface down
    ifconfig $sta_interface up

    # start wpa_supplicant
    ${WPA_SUPPLICANT_SCRIPT} ${sta_interface} ${WPA_SUPPLICANT_CONFIG_FILE}
    echo 3 > /proc/sys/kernel/printk

    log "finish STA mode"
    echo `date` "finish ${sta_interface} STA ssid=${SSID_NAME}" >> ${LOG_FILE}
}

wifi_apsta_mode()
{
    log "SET wifi APSTA mode"
    echo `date` "start ${ap_interface} APSTA mode" >> ${LOG_FILE}

    killall -9 udhcpc wpa_supplicant hostapd dnsmasq

    if [ -f ${CONFIGNET_FLAG} ]; then
        avacmd msg_cvt '{"type":"msgCvt", "wifi":{"state":"ap"}}' &
    fi

    # open sta
    update_wpa_conf_apsta

    # clear ip address
    ipaddr flush $sta_interface
    ifconfig $sta_interface down
    ifconfig $sta_interface up

    # start wpa_supplicant
    ${WPA_SUPPLICANT_SCRIPT} ${sta_interface} ${WPA_SUPPLICANT_CONFIG_FILE}

    echo 3 > /proc/sys/kernel/printk

    # open ap
    ipaddr flush $ap_interface
    ifconfig $ap_interface down
    ifconfig $ap_interface up
    ifconfig $ap_interface ${GATEWAY} netmask ${NETMASK}

    # start hostapd
    get_ssid
    sed -e "s/AP_IF_NAME/${ap_interface}/" -e "s/SSID_NAME/${SSID_NAME}/" -e "s/CHANNEL/${CHANNEL}/" /etc/wifi/hostapd.conf > /tmp/hostapd.conf
    mkdir -p /var/run/hostapd
    hostapd /tmp/hostapd.conf -B

    # sed dnsmasq configure file use ap interface
    sed "s/AP_IF_NAME/${ap_interface}/" /etc/wifi/dnsmasq.conf > /tmp/dnsmasq.conf
    echo -n "" > /tmp/dnsmasq.leases
    dnsmasq -C /tmp/dnsmasq.conf -x /tmp/dnsmasq.pid

    log "finish APSTA mode"
    echo `date` "finish ${ap_interface} APSTA ssid=${SSID_NAME}" >> ${LOG_FILE}
}

channel_sync()
{
    log "start channel sync"
    echo `date` "start channel sync" >> ${LOG_FILE}

    freq=`wpa_cli status |grep freq | cut -d '=' -f 2`
    freq_base="2412"
    freq_width="5"
    ap_channel=$(($(($freq - $freq_base)) / $freq_width))
    let ap_channel=$ap_channel+1
    log "ap_channel:$ap_channel"

    killall -9 hostapd dnsmasq
    ifconfig $ap_interface down

    # open ap
    ifconfig $ap_interface up
    ifconfig $ap_interface ${GATEWAY} netmask ${NETMASK}

    # AP mode
    get_ssid
    sed -e "s/AP_IF_NAME/${ap_interface}/" -e "s/SSID_NAME/${SSID_NAME}/" -e "s/CHANNEL/${ap_channel}/" /etc/wifi/hostapd.conf > /tmp/hostapd.conf
    mkdir -p /var/run/hostapd
    hostapd /tmp/hostapd.conf -B

    sed "s/AP_IF_NAME/${ap_interface}/" /etc/wifi/dnsmasq.conf > /tmp/dnsmasq.conf
    echo -n "" > /tmp/dnsmasq.leases
    dnsmasq -C /tmp/dnsmasq.conf -x /tmp/dnsmasq.pid

    log "finish channel sync $ap_channel"
    echo `date` "finish channel sync $ap_channel" >> ${LOG_FILE}
}

# 开启防火墙
# INPUT规则链中，允许udp 54321目的端口包通过
# OUTPUT规则链中，允许udp 54321源端口包通过
firewall_open()
{
    iptables -F
    iptables -P INPUT DROP
    iptables -A INPUT -s 127.0.0.1 -d 127.0.0.1 -j ACCEPT
    iptables -A INPUT -p udp --dport 54321 -j ACCEPT

    iptables -P OUTPUT DROP
    iptables -A OUTPUT -s 127.0.0.1 -d 127.0.0.1 -j ACCEPT
    iptables -A OUTPUT -p udp --sport 54321 -j ACCEPT
}

# 关闭防火墙
firewall_close()
{
    iptables -F
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
}

select_hidden_ssid()
{
    log "Connecting Hidden_ssid"
    echo `date` "select hidden ssid" >> ${LOG_FILE}

    hide_ssid=$1
    hide_bssid=$2

    log "hide_ssid: $hide_ssid"
    log "hide_bssid: $hide_bssid"

    update_wpa_conf_select_hidden "$hide_ssid" "$hide_bssid"
    log `cat $WPA_SUPPLICANT_CONFIG_FILE`

    #stop uap sta_interface
    killall -9 udhcpc wpa_supplicant
    ifconfig $sta_interface down
    ifconfig $sta_interface up
    ipaddr flush $sta_interface
    #iwconfig $sta_interface mode Managed

    # start wpa_supplicant
    ${WPA_SUPPLICANT_SCRIPT} ${sta_interface} ${WPA_SUPPLICANT_CONFIG_FILE}

    # start get ip
    get_ip

    # 连上隐藏SSID时，开启防火墙
    if [ x"$ip" != x ]; then
        firewall_open
    fi

    get_bind_status
    if [ x"$ip" != x ] && [ x"$bind_status" != x"ok" ]; then
        channel_sync
    fi

    wpa_cli -i $sta_interface list_network
    log "end_time: select hidden ssid"
    echo `date` "finish select hidden ssid" >> ${LOG_FILE}
}

select_master_ssid()
{
    log "Connecting Master_ssid"
    echo `date` "select master ssid" >> ${LOG_FILE}
    rm -f ${AP_FLAG}

    miio_ssid=$1
    passwd_b64=$2
    miio_ssid_5g=$3
    miio_passwd_5g=$4

    if [ -f ${CONFIGNET_FLAG} ]; then
        if [ -f /usr/bin/bt_init.sh ]; then
            killall -9 dreame_bt
            hciconfig hci0 down
        fi
        avacmd msg_cvt '{"type":"msgCvt", "wifi":{"state":"station"}}' &
    fi

    update_wpa_conf_select_master "$miio_ssid" "$passwd_b64" "$miio_ssid_5g" "$miio_passwd_5g"
    #log `cat $WPA_SUPPLICANT_CONFIG_FILE`

    #stop uap sta_interface
    killall -9 udhcpc wpa_supplicant hostapd dnsmasq

    # restart wifi driver
    /usr/bin/wifi_act.sh rmmod
    /etc/init.d/wifi.sh

    # clear ip address
    ipaddr flush $sta_interface
    ipaddr flush $ap_interface

    ifconfig $ap_interface down
    ifconfig $sta_interface down

    ifconfig $sta_interface up
    #iwconfig $sta_interface mode Managed

    # start wpa_supplicant
    ${WPA_SUPPLICANT_SCRIPT} ${sta_interface} ${WPA_SUPPLICANT_CONFIG_FILE}

    # 关闭防火墙
    firewall_close

    # start get ip
    iotflag=`cat $IOT_FLAG`
    if [ "x$iotflag" == "xdmiot" ] || [ "x$iotflag" == "xtyiot" ]; then
        for i in `seq 1 27`
        do
            ip=`wpa_cli status | grep ip_address | cut -d '=' -f 2`
            if [ "x$ip" == "x" ]; then
                log "ip not ready"
                sleep 1
            else
                break
            fi
        done
    else
        get_ip
    fi
    log `wpa_cli -i $sta_interface list_network`
    log "end_time: select master ssid"
    echo `date` "finish select master ssid" >> ${LOG_FILE}
}

get_master_network()
{
    key_mgmt=`sed -n '/^key_mgmt=/p' ${WIFI_CONF_FILE}`
    key_mgmt=${key_mgmt##*key_mgmt=}
    if [ "$key_mgmt" == "NONE" ]; then
        miio_passwd=""
        passwd_b64=""
    else
        miio_passwd=`sed -n '/^psk=/p' ${WIFI_CONF_FILE}`
        miio_passwd=${miio_passwd#*psk=}
        if [ ${#miio_passwd} -ge 66 ]; then
            miio_passwd=${miio_passwd#*\"}
            miio_passwd=${miio_passwd%\"*}
        fi

        passwd_b64=`sed -n '/^#pwd_b64=/p' ${WIFI_CONF_FILE}`
        passwd_b64=${passwd_b64#*pwd_b64=}
    fi
    miio_ssid=`sed -n '/^ssid=/p' ${WIFI_CONF_FILE}`
    miio_ssid=${miio_ssid#*ssid=\"}
    miio_ssid=${miio_ssid%\"*}

    key_mgmt_5g=`sed -n '/^key_mgmt_5g=/p' ${WIFI_CONF_FILE}`
    key_mgmt_5g=${key_mgmt_5g##*key_mgmt_5g=}
    if [ "$key_mgmt_5g" == "NONE" ]; then
        miio_passwd_5g=""
    else
        miio_passwd_5g=`sed -n '/^psk_5g=/p' ${WIFI_CONF_FILE}`
        miio_passwd_5g=${miio_passwd_5g#*psk_5g=}
    fi
    miio_ssid_5g=`sed -n '/^ssid_5g=/p' ${WIFI_CONF_FILE}`
    miio_ssid_5g=${miio_ssid_5g#*ssid_5g=\"}
    miio_ssid_5g=${miio_ssid_5g%\"*}
}

# wifi_reconnect(offline time = 15min)
# restart wpa_supplicant dhcp/dns and network
wifi_reconnect()
{
    ifconfig $sta_interface down
    ifconfig $sta_interface up

    killall -9 wpa_supplicant udhcpc
    sleep 1
    ${WPA_SUPPLICANT_SCRIPT} ${sta_interface} ${WPA_SUPPLICANT_CONFIG_FILE}
    sleep 1
    get_ip
    #sleep 1

    # 重启dns，清除dns缓存
    #/etc/init.d/network restart

    #sleep 1
}

# wifi_reload (offline time = 60min)
# reload kernel of wifi
# restart wpa_supplicant dhcp/dns and network
# restart miio_client
wifi_reload()
{
    # 重启驱动
    ifconfig $sta_interface down
    sleep 1
    /usr/bin/wifi_act.sh rmmod
    sleep 2
    /etc/init.d/wifi.sh
    sleep 1
    ifconfig $sta_interface up
    sleep 1

    wifi_reconnect

    # 重启OT
    /etc/rc.d/miio.sh stop
    sleep 1
    /etc/rc.d/miio.sh
}

start()
{
    get_bind_status

    if [ x"$1" = x"SET_AP_MODE" ]; then
        wifi_ap_mode
    fi
    if [ x"$1" = x"SET_APSTA_MODE" ]; then
        wifi_apsta_mode
    fi
    if [ x"$1" = x"CLOSE_STA_MODE" ]; then
        wifi_close_sta_mode
    fi

    if [ x"$1" = x"SELECT_HIDDEN" ]; then
        hide_ssid=$2
        hide_bssid=$3
        select_hidden_ssid "$hide_ssid" "$hide_bssid"
    fi
    if [ x"$1" = x"SELECT_MASTER" ]; then
        get_master_network
        select_master_ssid "$miio_ssid" "$passwd_b64" "$miio_ssid_5g" "$miio_passwd_5g"
    fi

    if [ x"$1" = x"WIFI_RECONNECT" ]; then
        #wifi_reconnect
        exit 0
    fi
    if [ x"$1" = x"WIFI_RELOAD" ]; then
        #wifi_reload
        touch ${WIFI_RELOAD} > /dev/null 2>&1
    fi

    if [ x"$bind_status" = x"ok" ] && [ "$#" = 0 ]; then
        get_master_network
        select_master_ssid "$miio_ssid" "$passwd_b64" "$miio_ssid_5g" "$miio_passwd_5g"
    fi
    if [ x"$bind_status" != x"ok" ] && [ "$#" = 0 ]; then
        if [ $MIIO_NET_AUTO_PROVISION -eq 1 ]; then
            wifi_apsta_mode
        else
#            wifi_ap_mode
            wifi_sta_mode
        fi
    fi
}

start $1 $2 $3
