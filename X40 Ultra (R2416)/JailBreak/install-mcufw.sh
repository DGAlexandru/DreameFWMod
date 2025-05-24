#!/bin/sh

if [  -f /misc/mcu.bin ]; then
    mkdir -p /tmp/update
    cp /misc/mcu.bin /tmp/update
    if [  -f /misc/UI.bin ]; then
        cp /misc/UI.bin /tmp/update/
    fi
    if [  -f /misc/UIMA.bin ]; then
        cp /misc/UI*.bin /tmp/update/
    fi
    echo 1 > /tmp/update/only_update_mcu_mark
    /etc/rc.d/ava.sh "ota"
    sleep 5
    avacmd ota  '{"type": "ota", "cmd": "report_upgrade_status", "status": "AVA_UNPACK_OK", "result": "ok"}'
else
    echo "(!!!) mcu.bin not found"
fi
