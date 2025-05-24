# DreameFWMod
<b>Scripts to automate the modding of Dreame Vacuum Robots's FirmWare.</b>
</br>This is an alternative way of having a rooted robot which is as close as it can be to the original FW, as opposed to DustBuilder's version which removes for the example the option to have remote video access / live camera from your robot.
</br>Having it modded like this allows you to switch between OnLine (Cloud, original App) and OffLine (<a href="https://github.com/DGAlexandru/NoCloud">NoCloud</a> or Valetudo) at any time, it requires only a command and a robot reboot.
<h2>Usage:</h2>
You need an original, unaltered image of the RootFS to be able to create the modded version.
</br>DustBuilder's RootFS versions are already (extremely) modified so they're of no use. Actually my mod is based also on things found in DustBuilder's image and "diff.txt" file.
</br>To get the original FW you could use DustBuilder to jailbreak your Dreame vacuum robot, but in the process DON'T also update boot2, respectively rootfs2; try also without updating toc1. (oem prep command is needed, for an easier rooting process, even if it corrupts the env-redundant partition)
</br>Once you have serial console or ssh access to the robot, you can save boot2 and rootfs2 partitions with dd for example.
</br>There are also other ways of dumping the original images, but the easy way of doing it is to use DustBuilder's way :P
</br>Then use my script to have an almost original version of the FW for that version, but with serial console and SSH access and then connect the robot to the Cloud, using the original Dreame app and choose to update it's FW.
</br>Get the download link from the LOGs from the robot, then use that file to unzip it (password protected) and to decrypt it. All the needed steps to do this are in the scripts that Dreame uses for the FW update process - so all you have to do is to search for them on your robot OS.
</br>Now you should have boot.img, rootfs.img, toc0 and toc1 fex files and also mcu.bin files (for different sub-versions from that family of robots).
</br>Again, check the original Dreame scripts to understand what each file is used for and how.
</br>Now, with the latest FW's rootfs img file, you can rerun the JailBreak script to have it modified for serial console and SSH access.

<h2>Ver 1.0 - 20/05/2025</h2>
<b>Supports the following Dreame Vacuum Robots:</b>
<ol>
<li>L20 Ultra FW ver 4.3.9_1639 (MR813 version: S/N with R2390 / R2394; essentially an R2338 = L10s Pro Ultra Heat that can also detach mops and with an increased vacuum power)</li>
<li>X40 Ultra FW ver 4.3.9_1702 (MR813 version; S/N with: R2449, but works with any R2416 family member)</li>
</ol>
<h2>Remarks:</h2>
<ul><li>As L20 Ultra is not supported by DustBuilder and they don't seem interested in doing it (I tried several times to contact Denis to work both on it - not even a reply back :|), currently I might be the only one who has a solution to root / JailBreak L20 Ultra R239x, so for now I won't release the link to the current FW version - so I can "recover the time" I've spent on research.</li>
<li>FW ver 4.3.9_1702 for X40 is currently available at: https://oss.iot.dreame.tech/pd/fw/000000/ali_dreame/dreame.vacuum.r2449a/4d196bfc977a072054112e45ed6eb9c4202503220714-_.bin . Replace "-" with "2" and last "_" with another digit (yes, there are 10 variants in total, only one works).</li>
</ul>
