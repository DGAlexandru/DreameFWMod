#!/bin/bash -x

#Init
ROOTin=rootfs.img
SOURCEdir=JailBreak
DESTdir=temp-rootfs
ROOTtmp=root_tmp.img
ROOT=rootfsL20.img
RELEASE=1639

#Cleanup of old data
rm -rf $DESTdir
rm $ROOT

#Deflating original RootFS
unsquashfs -d $DESTdir $ROOTin

#Customizations
cp $SOURCEdir/mcu.bin $DESTdir/misc/
cp $SOURCEdir/authorized_keys $DESTdir/misc/

echo -e '#!/bin/sh\n/bin/login -f root\n' > $DESTdir/bin/dustshell
chmod +xr $DESTdir/bin/dustshell

cp $SOURCEdir/banner $DESTdir/etc/
sed -i -e 's|release|$RELEASE|g' $DESTdir/etc/hostname
cp $SOURCEdir/hosts $DESTdir/misc/

sed -i -e 's|# Put a getty on the serial port|&\n::respawn:/sbin/getty -n -l /bin/dustshell 115200 -L ttyS0|g' $DESTdir/etc/inittab

cp $SOURCEdir/nsswitch.conf $DESTdir/etc/

sed -i -e 's|source /usr/bin/config|&\n\nif [  ! -f /mnt/misc/authorized_keys ]; then\n    cp /misc/authorized_keys /mnt/misc/authorized_keys\nfi\n\nmkdir -p /tmp/.ssh/\ncp /mnt/misc/authorized_keys /tmp/.ssh/\n\n# check if password login for ssh should be disabled\nif [  -f /mnt/misc/ssh_disable_passwords ]; then\n    dropbear -s \&\nelse\n    dropbear \&\nfi|g' $DESTdir/etc/rc.d/dropbear.sh

##Reduce disk wear by moving LOGs to /tmp
##Already resolved for L20 as we create this files later (L20 Ultra doesn't have support for MIIOT, so we manually add it)
##sed -i -e 's|=/data/log/|=/tmp/log/|g' $DESTdir/etc/rc.d/miio.sh
##sed -i -e 's|=/data/log/|=/tmp/log/|g' $DESTdir/etc/rc.d/miio_monitor.sh

sed -i -e 's|:/sbin"|:/sbin:/data/bin"|g' $DESTdir/etc/rc.sysinit
sed -i -e 's|/etc/init.d/mount_misc.sh|&\nif [  -f /data/_root.sh ]; then\n    /data/_root.sh \&\nfi|g' $DESTdir/etc/rc.sysinit

read -r -d '' TXT << EOF
/etc/rc.d/dropbear.sh \&\n\
if [  -f /data/_root_postboot.sh ]; then\n\
    /data/_root_postboot.sh \&\n\
#If we don\'t find the above file then maybe /data was wiped out so as a FailSafe we\'ll configure it here for OnLine mode\n\
else\n\
    echo -e "\\\n************************\\\n* FailSafe OnLine mode *\\\n************************\\\n"\n\
    echo "nameserver 114.114.114.114" >> /etc/resolv.conf\n\
    #cp /misc/miio_client_helper_nomqtt.sh /tmp/root/\n\
    cp /misc/network_hook.sh /tmp/root/\n\
    #cp /misc/miio_client /tmp/root/\n\
fi
EOF
sed -i -e "s|/etc/init.d/wifi_ap_record.sh >/dev/null 2>\&1 \&|&\n${TXT}|g" $DESTdir/etc/rc.sysinit

cp $SOURCEdir/_root_postboot.sh.tpl $DESTdir/misc/
cp $SOURCEdir/how_to_modify.txt $DESTdir/misc/
cp $SOURCEdir/htop $DESTdir/usr/bin/
cp $SOURCEdir/install-mcufw.sh $DESTdir/usr/bin/

#mv $DESTdir/usr/bin/miio_client $DESTdir/misc/
#ln -s /tmp/root/miio_client $DESTdir/usr/bin/miio_client
#cp $SOURCEdir/miio_clientNoCloud $DESTdir/misc/
cp $SOURCEdir/miio_clientNoCloud $DESTdir/usr/bin/miio_client

cp $SOURCEdir/agent_client $DESTdir/bin/
cp $SOURCEdir/miio_agent $DESTdir/bin/

#mv $DESTdir/usr/bin/miio_client_helper_nomqtt.sh $DESTdir/misc/
#ln -s /tmp/root/miio_client_helper_nomqtt.sh $DESTdir/usr/bin/miio_client_helper_nomqtt.sh
#cp $SOURCEdir/miio_client_helper_NoCloud.sh $DESTdir/misc/
cp $SOURCEdir/miio_client_helper_NoCloud.sh $DESTdir/usr/bin/miio_client_helper_nomqtt.sh

cp $SOURCEdir/miio_bt $DESTdir/usr/bin/
cp $SOURCEdir/miio_recv_line $DESTdir/usr/bin/
cp $SOURCEdir/miio_sdk.sh $DESTdir/usr/bin/
cp $SOURCEdir/miio_send_line $DESTdir/usr/bin/

#cp $SOURCEdir/wifi_start.sh $DESTdir/usr/bin/

cp $SOURCEdir/mi_tracking.sh $DESTdir/etc/rc.d
cp $SOURCEdir/miio.sh $DESTdir/etc/rc.d
cp $SOURCEdir/miio_monitor.sh $DESTdir/etc/rc.d

#cp $SOURCEdir/libjson-c.so.2 $DESTdir/misc/
#ln -s /tmp/root/libjson-c.so.2 $DESTdir/usr/lib/libjson-c.so.2
ln -s libjson-c.so.3.0.1 $DESTdir/usr/lib/libjson-c.so.2

cp $SOURCEdir/nano $DESTdir/usr/bin/
cp $SOURCEdir/libncurses.so.5.9 $DESTdir/usr/lib/
#ln -s libncurses.so.5.9 $DESTdir/usr/lib/libncurses.so.5

mv $DESTdir/usr/bin/network_hook.sh $DESTdir/misc/
ln -s /tmp/root/network_hook.sh $DESTdir/usr/bin/network_hook.sh

mkdir -p $DESTdir/usr/local/bin/
mkdir -p $DESTdir/usr/local/sbin/

cp $SOURCEdir/dbclient $DESTdir/usr/local/bin/
cp $SOURCEdir/scp $DESTdir/usr/local/bin/
cp $SOURCEdir/dropbear $DESTdir/usr/local/sbin/

cp -r $SOURCEdir/terminfo $DESTdir/usr/share/terminfo

sed -i -e 's|echo "nameserver 114.114.114.114" >> $RESOLV_CONF|#&|g' $DESTdir/usr/share/udhcpc/default.script

#Preparing environment
rm $DESTdir/dev/console

#Building new RootFS img
mksquashfs $DESTdir $ROOTtmp -noappend -root-owned -comp xz -b 256k -p 'dev d 755 0 0' -p 'dev/console c 600 0 0 5 1'

#Optimising img for eMMC
#Do we need this? The RootFs file was created with a block size of 256k, which is bigger than 128k :P
dd if=$ROOTtmp of=$ROOT bs=128k conv=sync

#Cleanup of temporary data
rm $ROOTtmp
