#!/bin/sh

#Stop formating /data when user changes
mkdir -p /data/test/
touch /data/test/ava.sh

#Stop formating /data when there are more than 3 ava crashes
if [ -f /data/ava_reboot_cnt ]; then
    if [[ $(cat /data/ava_reboot_cnt) -eq 2 ]]; then
        echo -e "Ava Reboot Count is 2.\nCheck what's going on! \nResetting..."
        rm /data/ava_reboot_cnt
    fi
fi


if [  -f /data/OnLine ]; then
    echo -e "\n************************\n* We're in OnLine mode *\n************************\n"
    echo "nameserver 114.114.114.114" >> /etc/resolv.conf
    #cp /misc/miio_client_helper_nomqtt.sh /tmp/root/
    cp /misc/network_hook.sh /tmp/root/
    #cp /misc/miio_client /tmp/root/

else
    echo -e "\n*************************\n* We're in NoCloud mode *\n*************************\n"
    # Interestingly, the iw command does not always have the same effect as these module parameters
    # It is expected that some of these will fail as the robot has only one of those modules
    echo 0 > /sys/module/8189fs/parameters/rtw_power_mgnt
    #echo 0 > /sys/module/8188fu/parameters/rtw_power_mgnt
    #echo 0 > /sys/module/8723ds/parameters/rtw_power_mgnt

    iw dev wlan0 set power_save off

    cp /misc/hosts /tmp/root/etc/hosts
    #cp /misc/miio_client_helper_NoCloud.sh /tmp/root/miio_client_helper_nomqtt.sh
    sed -e 's|elif \[ "$1" == "iot_connected" \]; then|&\n    exit 0|gi;s|elif \[ "$1" == "iot_disconnected" \]; then|&\n    exit 0|g' /misc/network_hook.sh > /tmp/root/network_hook.sh
    #cp /misc/miio_clientNoCloud /tmp/root/miio_client

    if [  -f /data/config/ava/iot.flag ] && grep -q "dmiot" /data/config/ava/iot.flag; then
        rm /data/config/ava/iot.flag
    fi

    if [  ! "$(readlink /data/config/system/localtime)" -ef "/usr/share/zoneinfo/UTC" ]; then
        rm /data/config/system/localtime
        ln -s /usr/share/zoneinfo/UTC /data/config/system/localtime
    fi

    if [  -f /data/NoCloud ]; then
        NoCloud_CONFIG_PATH=/data/NoCloud_config.json /data/NoCloud > /dev/null 2>&1 &
    fi
fi

#Make sure ava is alive
if [[ ! $(pidof ava) ]]; then
    DEVICE_NAME=`jsonpath -i /etc/os-release -e "@.product"`
    ava -f /ava/conf/${DEVICE_NAME}.conf force &
fi
