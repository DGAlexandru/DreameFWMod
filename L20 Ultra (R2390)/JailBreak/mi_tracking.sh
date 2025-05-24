#!/bin/sh
#
# author: qianmengnan
# date: 2023-12-25
# version: 0.0.1
# eg:
#   /etc/rc.d/mi_tracking.sh "report" "system_fault" "{\"fault_type\":\"Algorithm process crashes\"}" &
#   /etc/rc.d/mi_tracking.sh "report" "upgrade_fault" "{\"fault_type\":\"Download failed\"}" &
#   /etc/rc.d/mi_tracking.sh "report" "wifi_fault"
#
#   /etc/rc.d/mi_tracking.sh "record" "Offline1"
#   /etc/rc.d/mi_tracking.sh "record" "NO IP adress"
#

source /usr/bin/config disable_log
source /usr/bin/net_config

MI_WIFI_FAULT_LOG="/data/log/mi_tracking_wifistatus.data"
#TEST_LOG="/data/log/mi_tracking_process.log"

#current_time=$(date +"%Y-%m-%d %H:%M:%S")

if [ "${MIIO_SDK_MJAC}" != "true" ]; then
    #echo "Not MIIO_SDK_MJAC" >> "$TEST_LOG"
    exit 0
fi

file_count=`wc -l < "$MI_WIFI_FAULT_LOG"`
if [ "$file_count" -lt 2 ]; then
    # 如果文件不存在或者文件行数少于2，则添加足够多的空行
    echo -e "0" >> "$MI_WIFI_FAULT_LOG"
    echo -e "0" >> "$MI_WIFI_FAULT_LOG"
    #echo "add empty line" >> "$TEST_LOG"
fi

if [ "$1" == "report" ]; then
    if [ "$2" == "system_fault" ] || [ "$2" == "upgrade_fault" ]; then
        /ava/script/curl_server.sh "mi_tracking" "$2" "$3" &
        #echo "[$current_time], report:[$2][$3]" >> "$TEST_LOG"
    elif [ "$2" == "wifi_fault" ]; then
        if [ -f "$MI_WIFI_FAULT_LOG" ]; then
            #发布完成后清空
            FIST_LINE=$(sed -n '1p' "$MI_WIFI_FAULT_LOG")
            if [ "$FIST_LINE" != "0" ]; then
                /ava/script/curl_server.sh "mi_tracking" "wifi_fault" "{\"fault_type\":\"$FIST_LINE\"}" &
                sed -i "1s/.*/0/" "$MI_WIFI_FAULT_LOG" &
                #PRINT="{\"fault_type\":\"$FIST_LINE\"}"
                #echo "[$current_time], report:[wifi_fault][$PRINT]" >> "$TEST_LOG"
            fi
            SECOND_LINE=$(sed -n '2p' "$MI_WIFI_FAULT_LOG")
            if [ "$SECOND_LINE" == "Offline1" ]; then
                /ava/script/curl_server.sh "mi_tracking" "wifi_fault" "{\"fault_type\":\"Offline\",\"value\":1}" &
                sed -i "2s/.*/0/" "$MI_WIFI_FAULT_LOG" &
                #echo "[$current_time], report:[wifi_fault][Offline][1]" >> "$TEST_LOG"
            elif [ "$SECOND_LINE" == "Offline2" ]; then
                /ava/script/curl_server.sh "mi_tracking" "wifi_fault" "{\"fault_type\":\"Offline\",\"value\":2}" &
                sed -i "2s/.*/0/" "$MI_WIFI_FAULT_LOG" &
                #echo "[$current_time], report:[wifi_fault][Offline][2]" >> "$TEST_LOG"
            fi
        fi
    fi
elif [ "$1" == "record" ]; then
    if [ ! -f "$MI_WIFI_FAULT_LOG" ]; then
        touch "$MI_WIFI_FAULT_LOG" &
    fi

    line_count=`wc -l < "$MI_WIFI_FAULT_LOG"`
    if [ "$line_count" -lt 2 ]; then
        # 如果文件不存在或者文件行数少于2，则添加足够多的空行
        echo -e "0" >> "$MI_WIFI_FAULT_LOG"
        echo -e "0" >> "$MI_WIFI_FAULT_LOG"
    fi

    if [ "$2" == "Offline1" ] || [ "$2" == "Offline2" ]; then
        sed -i "2s/.*/$2/" "$MI_WIFI_FAULT_LOG" &
        #echo "[$current_time], record_222:[$2]" >> "$TEST_LOG"
    else
        sed -i "1s/.*/$2/" "$MI_WIFI_FAULT_LOG" &
        #echo "[$current_time], record_111:[$2]" >> "$TEST_LOG"
    fi
fi

awk '{if ($1 > 60) exit 1}' /proc/uptime && true || exit 1

echo [`cat /proc/uptime | cut -d " " -f 1`] $0 execute success!!!!!! | tee /dev/ttyS0 -a /tmp/log/sysinit.log > /dev/null 2>&1
