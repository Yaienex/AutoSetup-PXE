#!/bin/bash

echo -e "Bienvenue sur l'installateur automatique du serveur PXE, voulez-vous poursuivre en français (fr) ou en anglais (en)?\c"
read lg ;

if [[ "fr" == "$lg" ]] ; then
	source ./language/fr.sh
fi

if [[ "en" == "$lg" ]] ; then
	source ./language/en.sh
fi
echo
echo $enterMsg
read any

apt update
apt install isc-dhcp-server tftpd-hpa syslinux syslinux-efi nfs-kernel-server -y

echo ""
echo ""
echo $dhcpSetup

sudo mv /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.old
sudo touch /etc/dhcp/dhcpd.conf

sudo echo "ddns-update-style none; 

deny declines;

authoritative;

allow bootp;
allow booting;

option arch code 93 = unsigned integer 16;

#the subnet for IPv4
subnet 192.168.1.0 netmask 255.255.255.0 {
    if option arch = 00:07 {
      filename \"efi64/syslinux.efi\";
    } else if option arch = 00:06 {
      filename \"efi32/syslinux.efi\";
    } else {
      filename \"other/pxelinux.0\";
    }

    range 192.168.1.2 192.168.1.250;
    next-server 192.168.1.1;
}" >> /etc/dhcp/dhcpd.conf


echo $ipSetup
read device

sudo ip addr add 192.168.1.1/24 dev $device

### NEXT STEP TFTPD-HPA SERVER
sudo mv /etc/default/tftpd-hpa /etc/default/tftpd-hpa.old
sudo touch /etc/default/tftpd-hpa

echo
echo $tftpSetup
read directory;

if [ ! -d $directory ] ; then
	mkdir $directory;
fi

sudo echo "# /etc/default/tftp-hpa

TFTP_USERNAME=\"tftp\"
TFTP_DIRECTORY=\"$directory\"
TFTP_ADDRESS=\"192.168.1.1:69\"
TFTP_OPTIONS=\"--secure -v\"
RUN_DAEMON=\"yes\"
" >> /etc/default/tftpd-hpa

systemctl restart tftpd-hpa

### NFS Server
mv /etc/exports /etc/exports.old
sudo echo "$directory
192.168.1.1/24(async,no_root_squash,no_subtree_check,ro)" >>/etc/exports

systemctl restart nfs-kernel-server

### PXE files
mkdir $directory/{other,efi64,efi32}

cp /usr/lib/SYSLINUX.EFI/efi32/syslinux.efi $directory/efi32
cp /usr/lib/SYSLINUX.EFI/efi64/syslinux.efi $directory/efi64

cp /usr/lib/syslinux/modules/efi32/{libcom32.c32,libutil.c32,ldlinux.e32,vesamenu.c32} $directory/efi32/
cp /usr/lib/syslinux/modules/efi64/{libcom32.c32,libutil.c32,ldlinux.e64,vesamenu.c32} $directory/efi64/
cp /usr/lib/syslinux/modules/bios/{libcom32.c32,libutil.c32,vesamenu.c32} $directory/other

wget http://wiki.minet.net/pxelinux.0
mv pxelinux.0 $directory/other


mkdir $directory/efi64/pxelinux.cfg
touch $directory/efi64/pxelinux.cfg/{default,setup.menu,graphics.conf}
ln -s $directory/efi64/pxelinux.cfg/ $directory/efi32
ln -s $directory/efi64/pxelinux.cfg/ $directory/other


sudo echo "#Default menu for PXE boot
DEFAULT vesamenu.c32
PROMPT 0

MENU TITLE PXE Boot Menu
MENU INCLUDE pxelinux.cfg/graphics.conf
TIMEOUT 80
TOTALTIMEOUT 9000

LABEL LocalBoot
  MENU LABEL ^Exit the PXE
  LOCALBOOT 0xffff

LABEL SetupMenu
  MENU LABEL ^Setup Menu
  KERNEL vesamenu.c32
  APPEND pxelinux.cfg/graphics.conf pxelinux.cfg/setup.menu
" >> $directory/efi64/pxelinux.cfg/default

### Ubuntu 24 desktop
#wget https://releases.ubuntu.com/noble/ubuntu-24.04.1-desktop-amd64.iso
sudo mkdir  /mnt/loop
sudo mount -o loop ./ubuntu-24.04.1-desktop-amd64.iso /mnt/loop
sudo mkdir $directory/efi64/ubuntu24
sudo cp -r /mnt/loop/* $directory/efi64/ubuntu24
sudo cp -r /mnt/loop/.disk $directory/efi64/ubuntu24

sudo umount /mnt/loop



sudo echo "MENU TITLE PXE
  LABEL ^Return to main menu
    KERNEL vesamenu.c32
    APPEND pxelinux.cfg/default

  LABEL ^Install Ubuntu 24.04 desktop
  KERNEL ubuntu24/casper/vmlinuz
  INITRD ubuntu24/casper/initrd
  APPEND ip=dhcp netboot=nfs nfsroot=192.168.1.1:$directory/efi64/ubuntu24
" >> $directory/efi64/pxelinux.cfg/setup.menu

systemctl restart isc-dhcp-server

wget http://wiki.minet.net/minetpxe.png
mv minetpxe.png $directory/pxelinux.cfg
sudo echo "MENU BACKGROUND pxelinux.cfg/minetpxe.png">>$directory/efi64/pxelinux.cfg/graphics.conf
