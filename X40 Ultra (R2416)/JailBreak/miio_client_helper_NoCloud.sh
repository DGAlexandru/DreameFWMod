#!/bin/sh
#
# Date: 2021.08
# Version: 4.3.2_0.0.1
#
#set -x

source /usr/bin/config

WIFI_START_SCRIPT="/usr/bin/wifi_start.sh"
MIIO_RECV_LINE="/usr/bin/miio_recv_line"
MIIO_SEND_LINE="/usr/bin/miio_send_line"
WIFI_MAX_RETRY=3
WIFI_RETRY_INTERVAL=3

GLIBC_TIMEZONE_DIR="/usr/share/zoneinfo"
UCLIBC_TIMEZONE_DIR="/usr/share/zoneinfo"

LINK_TIMEZONE_FILE="/data/config/system/localtime"
TIMEZONE_DIR=$GLIBC_TIMEZONE_DIR

# 畅快连路由器默认隐藏SSID，请勿修改
MIIO_NET_PROVISIONER_SSID="25c829b1922d3123_miwifi"

if [ x"${AP_IF_NAME}" == x ]; then
    AP_IF_NAME=wlan1
fi

# 支持畅快连一键配网时，设置为1；否则设置为0
if [ "${MIIO_SDK_MJAC}" == "true" ]; then
    MIIO_NET_AUTO_PROVISION=0       # 使用安全芯片的产品(米家项目)，不支持一键配网功能
    if [ "${MIIO_SMART_CONFIG}" == "false" ]; then
        MIIO_NET_SMART_CONFIG=0     # 米家产品，默认支持畅快连同步改密，需要额外配置不支持同步改密
    else
        MIIO_NET_SMART_CONFIG=1     # 支持畅快连改密同步时，默认支持，设置为1；否则设置为0
    fi
else
    if [ "${MIIO_AUTO_PROVISION}" == "true" ]; then
        MIIO_NET_AUTO_PROVISION=1   # 非米家产品，需要额外配置支持一键配网功能
    else
        MIIO_NET_AUTO_PROVISION=0   # 非米家产品，默认不支持一键配网功能
    fi
    if [ "${MIIO_SMART_CONFIG}" == "true" ]; then
        MIIO_NET_SMART_CONFIG=1     # 非米家产品，默认不支持畅快连同步改密，需要额外配置支持同步改密
    else
        MIIO_NET_SMART_CONFIG=0     # 不支持畅快连改密同步时，设置为0；否则设置为1
    fi
fi

MIIO_NET_5G=0                   # 支持5G时，设置为1；否则设置为0
if [ x"$MIIO_AUTO_OTA" == x ]; then
    MIIO_AUTO_OTA=false         # 支持自动OTA升级时，设置为true；否则设置为false
fi

get_bind_status() {
    if [ -f ${WIFI_CONF_FILE} ]; then
        bind_status="ok"
    else
        bind_status=""
    fi

    log "bind_status: $bind_status"
}

check_password() {
    if [ x"$2" != x ]; then
        LEN=${#2}
        if [ ${LEN} -lt 8 ]; then
            log "pwd_5g error len:$LEN"
            return 2
        fi
    elif [ x"$1" != x ]; then
        LEN=${#1}
        if [ ${LEN} -lt 8 ]; then
            log "pwd error len:$LEN"
            return 1
        fi
    fi
    return 0
}

sanity_check() {
    if [ ! -e $WIFI_START_SCRIPT ]; then
        log "Can't find wifi_start.sh: $WIFI_START_SCRIPT"
        log 'Please change $WIFI_START_SCRIPT'
        exit 1
    fi
}

send_helper_ready() {
    ready_msg="{\"method\":\"_internal.helper_ready\"}"
    log $ready_msg
    $MIIO_SEND_LINE "$ready_msg"
}

request_dinfo() {
    # record miio_client running unnormally
    let req_dinfo_cnt++
    [ $req_dinfo_cnt -ge 100 ] && {
        record_events.sh iot_error 1001;
        killall -9 miio_client;
    }

    dinfo_did=`cat ${DEVICE_CONF_FILE} | grep -v ^# | grep did= | tail -1 | cut -d '=' -f 2`
    if [ -f /mnt/private/ULI/factory/key.txt ]; then
        dinfo_key=`cat /mnt/private/ULI/factory/key.txt`
    elif [ -f /mnt/private/ULI/factory/key.txt_bk ]; then
        dinfo_key=`cat /mnt/private/ULI/factory/key.txt_bk`
    fi
    if [ "x$dinfo_key" == "x" ]; then
        if [ -f ${NA_RELEASE} ]; then
            dinfo_key=`${NA_RELEASE} -c 2 -m MI_KEY | grep "MI_KEY:" | awk -F ':' '{print $2}'`
            log "key from tee"
        elif [ -f ${DREAME_SECURE_TOOL} ]; then
            dinfo_key=`${DREAME_SECURE_TOOL} -c 102 -s MI_KEY | grep "MI_KEY:" | awk -F ':' '{print $2}'`
            log "key from dreame_secure_tool"
        else
            log "key lost"
        fi
    else
        log "key from private"
    fi
    dinfo_vendor=`cat ${DEVICE_CONF_FILE} | grep -v ^# | grep vendor= | tail -1 | cut -d '=' -f 2`
    dinfo_mac=`cat ${DEVICE_CONF_FILE} | grep -v ^# | grep mac= | tail -1 | cut -d '=' -f 2`
    dinfo_model=`cat ${DEVICE_CONF_FILE} | grep -v ^# | grep model= | tail -1 | cut -d '=' -f 2`
    #for security chip
    dinfo_mjac_i2c=`cat ${DEVICE_CONF_FILE} | grep -v ^# | grep mjac_i2c= | tail -1 | cut -d '=' -f 2`
    dinfo_mjac_gpio=`cat ${DEVICE_CONF_FILE} | grep -v ^# | grep mjac_gpio= | tail -1 | cut -d '=' -f 2`
    #dinfo_pin_code="1234"      # 不支持OOB配网

    # 无感配网需要使用
    dinfo_sn=`cat /mnt/private/ULI/factory/sn.txt 2>/dev/null`

    if [ $MIIO_NET_SMART_CONFIG -eq 1 ]; then
        dinfo_wpa_intf="/var/run/wpa_supplicant/${WIFI_NODE}"
    fi
    if [ $MIIO_NET_AUTO_PROVISION -eq 1 ]; then
        dinfo_hostapd_intf="/var/run/hostapd/${AP_IF_NAME}"
    fi

    dinfo_uboot_ver=
    dinfo_ota_state=

    RESPONSE_DINFO="{\"method\":\"_internal.response_dinfo\",\"params\":{"
    if [ "${MIIO_SDK_MJAC}" != "true" ]; then
        if [ x$dinfo_did != x ]; then
            RESPONSE_DINFO="$RESPONSE_DINFO\"did\":$dinfo_did"
        fi
        if [ x$dinfo_key != x ]; then
            RESPONSE_DINFO="$RESPONSE_DINFO,\"key\":\"$dinfo_key\""
        fi
    else
        if [ x$dinfo_mjac_i2c != x ]; then
            RESPONSE_DINFO="$RESPONSE_DINFO\"mjac_i2c\":\"$dinfo_mjac_i2c\""
        fi
        if [ x$dinfo_mjac_gpio != x ]; then
            RESPONSE_DINFO="$RESPONSE_DINFO,\"mjac_gpio\":\"$dinfo_mjac_gpio\""
        fi
    fi

    if [ x$dinfo_vendor != x ]; then
        RESPONSE_DINFO="$RESPONSE_DINFO,\"vendor\":\"$dinfo_vendor\""
    fi
    if [ x$dinfo_mac != x ]; then
        RESPONSE_DINFO="$RESPONSE_DINFO,\"mac\":\"$dinfo_mac\""
    fi
    if [ x$dinfo_model != x ]; then
        RESPONSE_DINFO="$RESPONSE_DINFO,\"model\":\"$dinfo_model\""
    fi
    if [ x$dinfo_sn != x ]; then
        RESPONSE_DINFO="$RESPONSE_DINFO,\"sn\":\"$dinfo_sn\""
    fi
    if [ x$dinfo_uboot_ver != x ]; then
        RESPONSE_DINFO="$RESPONSE_DINFO,\"bootloader_ver\":\"$dinfo_uboot_ver\""
    fi
    if [ x$dinfo_wpa_intf != x ]; then
        RESPONSE_DINFO="$RESPONSE_DINFO,\"wpa_intf\":\"$dinfo_wpa_intf\""
    fi
    if [ x$dinfo_hostapd_intf != x ]; then
        RESPONSE_DINFO="$RESPONSE_DINFO,\"hostapd_intf\":\"$dinfo_hostapd_intf\""
    fi
    if [ x$dinfo_ota_state != x ]; then
        RESPONSE_DINFO="$RESPONSE_DINFO,\"ota_state\":\"$dinfo_ota_state\""
    fi
    # unsupport OOB
    #RESPONSE_DINFO="$RESPONSE_DINFO,\"OOB\":[{\"mode\":2,\"ctx\":\"\"},{\"mode\":3,\"ctx\":\"$dinfo_pin_code\"}]"
    RESPONSE_DINFO="$RESPONSE_DINFO,\"sc_type\":[0,1,2,3]"
    RESPONSE_DINFO="$RESPONSE_DINFO}}"

    log $RESPONSE_DINFO
    $MIIO_SEND_LINE "$RESPONSE_DINFO"
}

request_ot_config() {
    ot_config_string=$1
    ot_config_dir=${ot_config_string##*dir\":\"}
    ot_config_dir=${ot_config_dir%%\"*}
    dtoken_token=${ot_config_string##*ntoken\":\"}
    dtoken_token=${dtoken_token%%\"*}

    get_bind_status
    if [ x"$bind_status" != x"ok" ] ; then
        rm -rf ${MIIO_TOKEN_FILE}
        sync
    fi
    miio_token=`cat ${MIIO_TOKEN_FILE} 2>/dev/null`
    if [ x$miio_token = x ]; then
        echo ${dtoken_token} > ${MIIO_TOKEN_FILE}
        sync
        miio_token=${dtoken_token}
    fi

    miio_country=`cat ${MIIO_COUNTRY_FILE} 2>/dev/null`

    if [ -f ${WIFI_CONF_FILE} ]; then
        miio_ssid=`grep ^ssid ${WIFI_CONF_FILE}`
        miio_ssid=${miio_ssid#*ssid=\"}
        miio_ssid=${miio_ssid%\"*}
        miio_ssid=${miio_ssid//\\/\\\\}
        miio_ssid=${miio_ssid//\"/\\\"}

        miio_passwd=`grep ^psk ${WIFI_CONF_FILE}`
        miio_passwd=${miio_passwd#*psk=}
        echo ${miio_passwd} | grep -q '^".*"$'
        if [ $? -eq 0 ]; then
            miio_passwd=${miio_passwd#*\"}
            miio_passwd=${miio_passwd%\"*}
            miio_passwd=${miio_passwd//\\/\\\\}
            miio_passwd=${miio_passwd//\"/\\\"}
        fi
    fi

    if [ -f ${WIFI_CONF_FILE} ]; then
        miio_uid=`cat ${MIIO_UID_FILE}`
    fi

    RESPONSE_OT_CONFIG="{\"method\":\"_internal.res_ot_config\",\"params\":{"
    RESPONSE_OT_CONFIG="$RESPONSE_OT_CONFIG\"token\":\"$miio_token\""
    if [ x$miio_country != x ]; then
        RESPONSE_OT_CONFIG="$RESPONSE_OT_CONFIG,\"country\":\"$miio_country\""
    fi
    if [ x$miio_ssid != x ]; then
        RESPONSE_OT_CONFIG="$RESPONSE_OT_CONFIG,\"ssid\":\"$miio_ssid\""
    fi
    if [ x$miio_passwd != x ]; then
        RESPONSE_OT_CONFIG="$RESPONSE_OT_CONFIG,\"password\":\"$miio_passwd\""
    fi
    if [ x$miio_uid != x ]; then
        RESPONSE_OT_CONFIG="$RESPONSE_OT_CONFIG,\"uid\":$miio_uid"
    fi
    RESPONSE_OT_CONFIG="$RESPONSE_OT_CONFIG}}"

    log $RESPONSE_OT_CONFIG
    $MIIO_SEND_LINE "$RESPONSE_OT_CONFIG"
}

request_dtoken() {
    ot_config_string=$1
    ot_config_dir=${ot_config_string##*dir\":\"}
    ot_config_dir=${ot_config_dir%%\"*}
    dtoken_token=${ot_config_string##*ntoken\":\"}
    dtoken_token=${dtoken_token%%\"*}

    get_bind_status
    if [ x"$bind_status" != x"ok" ] ; then
        rm -rf ${MIIO_TOKEN_FILE}
        sync
    fi
    miio_token=`cat ${MIIO_TOKEN_FILE} 2>/dev/null`
    if [ x$miio_token = x ]; then
        echo ${dtoken_token} > ${MIIO_TOKEN_FILE}
        sync
        miio_token=${dtoken_token}
    fi

    miio_country=`cat ${MIIO_COUNTRY_FILE} 2>/dev/null`

    RESPONSE_DTOKEN="{\"method\":\"_internal.response_dtoken\",\"params\":\"${miio_token}\"}"
    RESPONSE_DCOUNTRY="{\"method\":\"_internal.response_dcountry\",\"params\":\"${miio_country}\"}"


    log $RESPONSE_DTOKEN
    $MIIO_SEND_LINE "$RESPONSE_DTOKEN"

    log $RESPONSE_DCOUNTRY
    $MIIO_SEND_LINE "$RESPONSE_DCOUNTRY"
}

req_wifi_conf_status() {
    get_bind_status
    if [ x"$bind_status" = x"ok" ] ; then
        REQ_WIFI_CONF_STATUS_RESPONSE="{\"method\":\"_internal.res_wifi_conf_status\",\"params\":1}"
    else
        if [ $MIIO_NET_AUTO_PROVISION -eq 1 ]; then
            REQ_WIFI_CONF_STATUS_RESPONSE="{\"method\":\"_internal.res_wifi_conf_status\",\"params\":3}"
        else
            REQ_WIFI_CONF_STATUS_RESPONSE="{\"method\":\"_internal.res_wifi_conf_status\",\"params\":0}"
        fi
    fi

    log $REQ_WIFI_CONF_STATUS_RESPONSE
    $MIIO_SEND_LINE "$REQ_WIFI_CONF_STATUS_RESPONSE"
}

update_dtoken() {
    update_token_string=$1
    update_dtoken=${update_token_string##*ntoken\":\"}
    update_token=${update_dtoken%%\"*}

    rm -rf ${MIIO_TOKEN_FILE}
    sync
    if [ x$update_token != x ]; then
        echo ${update_token} > ${MIIO_TOKEN_FILE}
        sync
    fi
    RESPONSE_UPDATE_TOKEN="{\"method\":\"_internal.token_updated\",\"params\":\"${update_token}\"}"

    $MIIO_SEND_LINE "$RESPONSE_UPDATE_TOKEN"
}

internal_info() {
    STRING=`wpa_cli status`
    ifname=${STRING#*\'}
    ifname=${ifname%%\'*}
    #log "ifname: $ifname"

    ssid=`wpa_cli status | grep -w '^ssid'`
    ssid=${ssid#*ssid=}
    ssid=$(echo -e "${ssid}" | sed -e 's/\\/\\\\/g' -e 's/\\\\\"/\\\"/g')
    #log "ssid: $ssid"

    bssid=`wpa_cli status | grep -w '^bssid' | awk -F "=" '{print $NF}'`
    bssid=`echo ${bssid} | tr '[:lower:]' '[:upper:]'`
    #log "bssid: $bssid"

    freq=`wpa_cli status | grep -w '^freq' | awk -F "=" '{print $NF}'`
    if [ "x$freq" = "x" ]; then
        freq=0
    fi
    #log "freq: $freq"

    rssi=`wpa_cli signal_poll | grep RSSI | cut -f 2 -d '='`
    if [ "x$rssi" = "x" ]; then
        rssi=0
    fi
    #log "rssi: $rssi"

    ip=${STRING##*ip_address=}
    ip=`echo ${ip} | cut -d ' ' -f 1`
    if [ x"$ip" = x"Selected" ]; then
        ip=
    fi
    #log "ip: $ip"

    STRING=`ifconfig ${ifname}`
    echo "${STRING}" | grep -q Mask
    if [ $? -eq 0 ]; then
        netmask=${STRING##*Mask:}
        netmask=`echo ${netmask} | cut -d ' ' -f 1`
    else
        netmask=""
    fi
    #log "netmask: $netmask"

    gw=`route -n | grep 'UG' | tr -s ' ' | cut -d ' ' -f 2`
    #log "gw: $gw"

    vendor=`grep vendor ${DEVICE_CONF_FILE} | cut -f 2 -d '=' | tr '[:lower:]' '[:upper:]'`
    sw_version=`cat /etc/os-release | jshon -e fw_arm_ver -u`
    if [ -z $sw_version ]; then
        sw_version="unknown"
    fi

    RESPONSE="{\"method\":\"_internal.info\",\"partner_id\":\"\",\"params\":{\
\"hw_ver\":\"Linux\",\"fw_ver\":\"$sw_version\",\"auto_ota\":$MIIO_AUTO_OTA,\
\"ap\":{\
\"ssid\":\"$ssid\",\"bssid\":\"$bssid\",\"rssi\":\"$rssi\",\"freq\":$freq\
},\
\"netif\":{\
\"localIp\":\"$ip\",\"mask\":\"$netmask\",\"gw\":\"$gw\"\
}}}"

    [ -n "$ip" ] && log "$RESPONSE"
    $MIIO_SEND_LINE "$RESPONSE"
}

save_wifi_conf() {
    if [ -f ${DEBUG_VERSION_FILE} ]; then
        log "set miio_ssid=$1, miio_passwd=$2, miio_ssid_5g=$3, miio_passwd_5g=$4, miio_uid=$5, miio_country=$6"
    else
        log "set miio_ssid=$1, miio_ssid_5g=$3, miio_uid=$5, miio_country=$6"
    fi

    rm -f ${WIFI_CONF_FILE}
    if [ x"$1" != x ]; then
        echo "ssid=\"$1\"" >> ${WIFI_CONF_FILE}

        if [ x"$2" != x ]; then
            psk_str=`wpa_passphrase "$1" "$2" | grep ^[[:space:]]*psk=`
            hex_psk=${psk_str#*psk=}
            echo $psk_str >> ${WIFI_CONF_FILE}
            pwd_b64=`echo -n "$2" | base64 | sed ':lable;N;s/\n//g;b lable'`
            echo "#pwd_b64=${pwd_b64}" >> ${WIFI_CONF_FILE}
            echo "key_mgmt=WPA" >> ${WIFI_CONF_FILE}
        else
            echo "key_mgmt=NONE" >> ${WIFI_CONF_FILE}
        fi
    fi

    if [ x"$3" != x ]; then
        echo "ssid_5g=\"$3\"" >> ${WIFI_CONF_FILE}

        if [ x"$4" != x ]; then
            psk_5g_str=`wpa_passphrase "$3" "$4" | grep ^[[:space:]]*psk=`
            echo ${psk_5g_str/psk/psk_5g} >> ${WIFI_CONF_FILE}
            echo "key_mgmt_5g=WPA" >> ${WIFI_CONF_FILE}
        else
            echo "key_mgmt_5g=NONE" >> ${WIFI_CONF_FILE}
        fi
    fi

    echo "$5" > ${MIIO_UID_FILE}
    echo "$6" > ${MIIO_COUNTRY_FILE}
    sync
}

clear_wifi_conf() {
    rm -f ${WIFI_CONF_FILE}
    rm -f ${MIIO_UID_FILE}
    rm -f ${MIIO_COUNTRY_FILE}
    sync
}

save_tz_conf() {
    if contains "$1" "../"; then
        return 0
    fi
    new_tz=$TIMEZONE_DIR/$1
    log $new_tz
    mkdir -p /data/config/system
    if [ -f $new_tz ]; then
        unlink $LINK_TIMEZONE_FILE
        ln -sf $new_tz $LINK_TIMEZONE_FILE
        log "timezone set success:$new_tz"
    else
        log "timezone is not exist:$new_tz"
    fi
}

wifi_start() {
    # TODO: add lock to /data/config/ava/iot.flag
    content=`cat $IOT_FLAG`
    if [ "x$content" == "x" ]; then
        echo $IOT_TYPE > $IOT_FLAG
        log "set SDK($content) to $IOT_FLAG"
    elif [ "x$content" != "x$IOT_TYPE" ];then
        log "other SDK($content) already set $IOT_FLAG"
        return
    else
        log "already set current SDK($content) to $IOT_FLAG"
    fi

    wifi_start_string=$1

    RESPONSE_WIFI_START=""

    miio_ssid=$(echo "$wifi_start_string" | jshon -e params -e ssid -u)
    miio_passwd=$(echo "$wifi_start_string" | jshon -e params -e passwd -u)
    miio_ssid_5g=$(echo "$wifi_start_string" | jshon -e params -e ssid_5g -u)
    miio_passwd_5g=$(echo "$wifi_start_string" | jshon -e params -e passwd_5g -u)
    miio_uid=$(echo "$wifi_start_string" | jshon -e params -e uid -u)
    miio_country=$(echo "$wifi_start_string" | jshon -e params -e country_domain -u)
    miio_tz=$(echo "$wifi_start_string" | jshon -e params -e tz -u)
    miio_bssid=$(echo "$wifi_start_string" | jshon -e params -e bssid -u)

    get_bind_status

    if [ $MIIO_NET_5G -eq 0 ]; then
        miio_ssid_5g=""
        miio_passwd_5g=""
    fi

    log "miio_ssid: $miio_ssid"
    log "miio_ssid_5g: $miio_ssid_5g"
    log "miio_uid: $miio_uid"
    log "miio_country: $miio_country"
    log "miio_tz: $miio_tz"
    log "miio_bssid: $miio_bssid"

    if [ x"$miio_ssid" != x"$MIIO_NET_PROVISIONER_SSID" ] && [ x"$miio_ssid_5g" != x"$MIIO_NET_PROVISIONER_SSID" ]; then
        save_wifi_conf "$miio_ssid" "$miio_passwd" "$miio_ssid_5g" "$miio_passwd_5g" "$miio_uid" "$miio_country"
        save_tz_conf "$miio_tz"
    fi

    CMD=$WIFI_START_SCRIPT
    RETRY=1
    WIFI_SUCC=0
    until [ $RETRY -gt $WIFI_MAX_RETRY ]
    do
        WIFI_SUCC=0
        rm -f ${WIFI_PWD_ERR} > /dev/null 2>&1
        log "Retry $RETRY: CMD=${CMD}"

        if [ x"$miio_ssid" = x"$MIIO_NET_PROVISIONER_SSID" ]; then
            ${CMD} "SELECT_HIDDEN" "$miio_ssid" "$miio_bssid"

            ip=`wpa_cli status | grep ip_address | cut -d '=' -f 2`
            if [ x"$ip" == x ];then
                WIFI_SUCC=1
            fi
            break
        else
            IOT=$(which iot)
            [ ${IOT} ] && {
                log "config net set miiot";
                iot_cli '{"type":"iot","mode":"ci","iot":"miiot"}';
            }

            check_password "$miio_passwd" "$miio_passwd_5g"
            check_ret=$?
            if [ "${MIIO_SDK_MJAC}" == "true" ] || [ ! ${IOT} ]; then
                [ ${check_ret} -ne 0 ] && { touch ${WIFI_PWD_ERR}; WIFI_SUCC=2; break;}

                # wifi flash_fastlight flash fast in sta mode
                if [ "$NEW_LIGHT_DISPLAY" == "yes" ]; then
                    set_wifi_light.sh flash
                else
                    set_wifi_light.sh flash_fast
                    if [ ${RETRY} -eq 1 ]; then
                        avacmd clb '{"type":"clb","cmd":"report_network_connect_mode","mode":10}' &
                    fi
                fi
                ${CMD} "SELECT_MASTER"

                ip=`wpa_cli status | grep ip_address | cut -d '=' -f 2`
                if [ x"$ip" == x ];then
                    WIFI_SUCC=2
                else
                    [ ${IOT} ] && iot_cli '{"type":"wifi","cmd":"sync_mode","mode":"sta"}'
                    break
               fi
            else
                if [ ${check_ret} -ne 0 ]; then
                    iot_cli '{"type":"iot","mode":"cn","cmd":"pwd_err"}'
                else
                    log "set iot connect ap:$miio_ssid"
                    #hex_ssid=`echo -n "$miio_ssid" | xxd -p -c 32`
                    #ssid_b64=`echo -n "$miio_ssid" | base64`
                    #pwd_b64=`echo -n "$miio_passwd" | base64`
                    #iot_cli "{\"type\":\"wifi\",\"cmd\":\"connect_ap\",\"ssid\":\"$hex_ssid\",\"ssid64\":\"$ssid_b64\",\"pwd\":\"$hex_psk\",\"pwd64\":\"$pwd_b64\",\"save_config\":true}"

                    wifi_proxy.sh ap_info "${miio_ssid}" "${miio_passwd}"
                fi
                break
            fi
        fi
        let RETRY=$RETRY+1
        sleep $WIFI_RETRY_INTERVAL
    done

    if [ $WIFI_SUCC -eq 0 ]; then
        STRING=`wpa_cli status`
        ifname=${STRING#*\'}
        ifname=${ifname%%\'*}

        ssid=`wpa_cli status | grep -w 'ssid' | awk -F "ssid=" '{print $2}'`
        ssid=$(echo -e ${ssid} | sed -e 's/\\/\\\\/g' -e 's/\\\\\"/\\\"/g')
        bssid=${STRING##*bssid=}
        bssid=`echo ${bssid} | cut -d ' ' -f 1 | tr '[:lower:]' '[:upper:]'`

        RESPONSE_WIFI_START="{\"method\":\"_internal.wifi_connected\",\"params\":{\"ssid\":\"$ssid\",\"bssid\":\"$bssid\",\"result\":\"ok\"}}"
    fi
    if [ $WIFI_SUCC -eq 2 ] && [ x"$bind_status" != x"ok" ]; then
        clear_wifi_conf
        if [ -f ${WIFI_PWD_ERR} ]; then
            rm -f ${WIFI_PWD_ERR}
            avacmd media '{"type":"media","cmd":"play","file_number":2}' &
            avacmd clb '{"type":"clb","cmd":"report_network_connect_mode","mode":3}' &
            avacmd msg_cvt '{"method":"local.status","params":"wifi_pwd_wrong"}' &
        fi
        #CMD=$WIFI_START_SCRIPT
        #log "Back to AP mode, CMD=${CMD}"
        #${CMD} "SET_AP_MODE"
        echo -n "FAIL" > ${CONFIGNET_FLAG}
        RESPONSE_WIFI_START="{\"method\":\"_internal.wifi_ap_mode\",\"params\":null}";
        log "config net failed"
    fi
    if [ $WIFI_SUCC -eq 1 ]; then
        RESPONSE_WIFI_START="{\"method\":\"_internal.wifi_connect_failed\",\"params\":{\"ssid\":\"$miio_ssid\",\"bssid\":\"$miio_bssid\",\"result\":\"error\"}}"
    fi

    log $RESPONSE_WIFI_START
    if [ x"$RESPONSE_WIFI_START" != x ]; then
        $MIIO_SEND_LINE "$RESPONSE_WIFI_START"
    fi
}

wifi_disconnect_req() {
    disconnect_wifi_str=$1
    ssid=$(echo "$disconnect_wifi_str" | jshon -e params -e ssid -u)
    bssid=$(echo "$disconnect_wifi_str" | jshon -e params -e bssid -u)

    get_bind_status

    log "hidden_ssid: $ssid"
    log "hidden_bssid: $bssid"
    log "bind_status: $bind_status"

    RESPONSE_DISCONNECT_WIFI="{\"method\":\"_internal.wifi_disconnect_resp\",\"params\":{\"ssid\":\"$ssid\",\"bssid\":\"$bssid\"}}";
    log $RESPONSE_DISCONNECT_WIFI
    $MIIO_SEND_LINE "$RESPONSE_DISCONNECT_WIFI"

    CMD=$WIFI_START_SCRIPT
    if [ x"$ssid" = x"$MIIO_NET_PROVISIONER_SSID" ]; then
        if [ x"$bind_status" = x"ok" ]; then
            ${CMD} "SELECT_MASTER"
        else
            ${CMD} "CLOSE_STA_MODE"
        fi
    fi
}

wifi_reconnect()
{
    CMD=$WIFI_START_SCRIPT
    ${CMD} "WIFI_RECONNECT"
}

wifi_reload()
{
    CMD=$WIFI_START_SCRIPT
    ${CMD} "WIFI_RELOAD"
}

main() {
    IOT_TYPE=miiot
    if [ ! -f $IOT_FLAG ]; then
        touch $IOT_FLAG
    fi

    while true; do
        BUF=`$MIIO_RECV_LINE`
        if [ $? -ne 0 ]; then
            sleep 1;
            continue
        elif [ x$BUF == x ]; then
            continue
        fi

        method=$(echo "$BUF" | jshon -e method -u)
        log "method: $method"

        if [ x"$method" = x"_internal.request_dinfo" ]; then
            request_dinfo "$BUF"
        elif [ x"$method" = x"_internal.request_ot_config" ]; then
            request_ot_config "$BUF"
        elif [ x"$method" = x"_internal.request_dtoken" ]; then
            request_dtoken "$BUF"
        elif [ x"$method" = x"_internal.req_wifi_conf_status" ]; then
            req_wifi_conf_status "$BUF"
        elif [ x"$method" = x"_internal.update_dtoken" ]; then
            update_dtoken "$BUF"
        elif [ x"$method" = x"_internal.info" ]; then
            internal_info "$BUF"
        elif [ x"$method" = x"_internal.config_tz" ]; then
            miio_tz=$(echo "$BUF" | jshon -e params -e tz -u -Q)
            save_tz_conf "$miio_tz"
        elif [ x"$method" = x"_internal.wifi_start" ]; then
            wifi_start "$BUF"
        elif [ x"$method" = x"_internal.wifi_disconnect_req" ]; then
            wifi_disconnect_req "$BUF"
        elif [ x"$method" = x"_internal.wifi_reconnect" ]; then
            wifi_reconnect
        elif [ x"$method" = x"_internal.wifi_reload" ]; then
            wifi_reload
        else
            log "Unknown cmd: $BUF"
        fi
    done
}

sanity_check
send_helper_ready
main
