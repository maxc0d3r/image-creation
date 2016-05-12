##########################################################################################
# Create AMI
##########################################################################################

export IMAGE_DIR=/tmp

for d in proc etc dev var/cache var/log var/lock var/loc/rpm sys; do
 mkdir -p /mnt/ec2-fs/$d
done

# Create the minimum devices
/sbin/MAKEDEV -d /mnt/ec2-fs/dev -x console
/sbin/MAKEDEV -d /mnt/ec2-fs/dev -x null
/sbin/MAKEDEV -d /mnt/ec2-fs/dev -x zero
/sbin/MAKEDEV -d /mnt/ec2-fs/dev -x urandom


# mount in other stuff
mount -o bind /dev/pts /mnt/ec2-fs/dev/pts
mount -o bind /dev/shm /mnt/ec2-fs/dev/shm
mount -o bind /proc /mnt/ec2-fs/proc
mount -o bind /sys /mnt/ec2-fs/sys


# Copy mdadm.conf
cp /tmp/mdadm.conf /mnt/ec2-fs/etc/mdadm.conf

# Create device mapping fstab
cp /tmp/fstab /mnt/ec2-fs/etc/fstab

##
export releasever=6.2
export arch=x86_64
export basearch=x86_64

cat << EOF >  $IMAGE_DIR/yum-xen.conf
[main]
cachedir=/var/cache/yum
debuglevel=2
logfile=/var/log/yum.log
exclude=*-debuginfo
gpgcheck=0
obsoletes=1
pkgpolicy=newest
distroverpkg=redhat-release
tolerant=1
exactarch=1
reposdir=/dev/null
metadata_expire=1800

[base]
name=CentOS-$releasever - Base
mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os
#baseurl=http://mirror.centos.org/centos/$releasever/os/$basearch/
gpgcheck=1
gpgkey=http://mirror.centos.org/centos/RPM-GPG-KEY-CentOS-6

#released updates 
[updates]
name=CentOS-$releasever - Updates
mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=updates
#baseurl=http://mirror.centos.org/centos/$releasever/updates/$basearch/
gpgcheck=1
gpgkey=http://mirror.centos.org/centos/RPM-GPG-KEY-CentOS-6

#additional packages that may be useful
[extras]
name=CentOS-$releasever - Extras
mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=extras
#baseurl=http://mirror.centos.org/centos/$releasever/extras/$basearch/
gpgcheck=1
gpgkey=http://mirror.centos.org/centos/RPM-GPG-KEY-CentOS-6

#additional packages that extend functionality of existing packages
[centosplus]
name=CentOS-$releasever - Plus
mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=centosplus
#baseurl=http://mirror.centos.org/centos/$releasever/centosplus/$basearch/
gpgcheck=1
enabled=0
gpgkey=http://mirror.centos.org/centos/RPM-GPG-KEY-CentOS-6

#contrib - packages by Centos Users
[contrib]
name=CentOS-$releasever - Contrib
mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=contrib
#baseurl=http://mirror.centos.org/centos/$releasever/contrib/$basearch/
gpgcheck=1
enabled=0
gpgkey=http://mirror.centos.org/centos/RPM-GPG-KEY-CentOS-6

EOF

# install the o/s
yum -c $IMAGE_DIR/yum-xen.conf --installroot=/mnt/ec2-fs -y groupinstall Base 
yum -c $IMAGE_DIR/yum-xen.conf --installroot=/mnt/ec2-fs -y install grub grubby e2fsprogs
yum -c $IMAGE_DIR/yum-xen.conf --installroot=/mnt/ec2-fs -y groupinstall "Ruby Support"
yum -c $IMAGE_DIR/yum-xen.conf --installroot=/mnt/ec2-fs -y groupinstall "Backup Client"	

# some more stuff we desparately need
yum -c $IMAGE_DIR/yum-xen.conf --installroot=/mnt/ec2-fs -y install ec2-utils *openssh* openssh-server yum-plugin-fastestmirror.noarch dhclient dhcp-common
yum -c $IMAGE_DIR/yum-xen.conf --installroot=/mnt/ec2-fs -y install sudo

# no se-linux yet
yum -c $IMAGE_DIR/yum-xen.conf --installroot=/mnt/ec2-fs -y install selinux-policy selinux-policy-targeted

# install xfs support
yum -c $IMAGE_DIR/yum-xen.conf --installroot=/mnt/ec2-fs -y install xfsprogs

# stuff required by cloud-init
yum -c $IMAGE_DIR/yum-xen.conf --installroot=/mnt/ec2-fs -y install python-cheetah python-configobj python-yaml

# redhat stuff
yum -c $IMAGE_DIR/yum-xen.conf --installroot=/mnt/ec2-fs -y install redhat-lsb

# no clue ;-)
yum -c $IMAGE_DIR/yum-xen.conf --installroot=/mnt/ec2-fs -y install nc

# install chef client
cp /etc/resolv.conf /mnt/ec2-fs/etc/resolv.conf
chroot /mnt/ec2-fs rpm -Uvh http://rbel.frameos.org/rbel6
yum -c $IMAGE_DIR/yum-xen.conf --installroot=/mnt/ec2-fs -y ruby ruby-devel ruby-ri ruby-rdoc ruby-shadow gcc gcc-c++ automake autoconf make curl dmidecode git

# cloud init
/usr/sbin/chroot /mnt/ec2-fs rpm -Uvh http://bashton.com/downloads/centos-ami/RPMS/x86_64/libyaml-0.1.3-1.0.el6_bashton.x86_64.rpm
/usr/sbin/chroot /mnt/ec2-fs rpm -Uvh http://bashton.com/downloads/centos-ami/RPMS/x86_64/PyYAML-3.09-5.5.el6_bashton.x86_64.rpm
/usr/sbin/chroot /mnt/ec2-fs rpm -Uvh http://bashton.com/downloads/centos-ami/RPMS/noarch/cloud-init-0.5.15-20.el6_bashton1.noarch.rpm
/usr/sbin/chroot /mnt/ec2-fs rpm -Uvh http://bashton.com/downloads/centos-ami/RPMS/noarch/ec2-utils-0.2-1.5bashton1.el6.noarch.rpm

/usr/sbin/chroot /mnt/ec2-fs <<EOF
 sed -i -e 's/\(preserve_hostname:\).*/\1 False/' /etc/cloud/cloud.cfg
 sed -i '/HOSTNAME/d' /etc/sysconfig/network
 rm /etc/hostname
 # DHCP provides resolv.conf
 echo "" > /etc/resolv.conf
 # Remove all mac address references
 rm /etc/udev/rules.d/70-persistent-net.rules
 sed -i '/HWADDR/d' /etc/sysconfig/network-scripts/ifcfg-eth0
 sed -i '/HOSTNAME/d' /etc/sysconfig/network-scripts/ifcfg-eth0
EOF

# install java and other rpms
cp /home/ec2-user/rpms/*rpm /mnt/ec2-fs/tmp
chroot /mnt/ec2-fs rpm -iv /tmp/*rpm
rm -f /mnt/ec2-fs/tmp/*rpm

/usr/sbin/chroot /mnt/ec2-fs /sbin/chkconfig sshd --add
/usr/sbin/chroot /mnt/ec2-fs /sbin/chkconfig --level 12345 sshd on

/usr/sbin/chroot /mnt/ec2-fs /sbin/chkconfig cloud-init --add
/usr/sbin/chroot /mnt/ec2-fs /sbin/chkconfig --level 12345 cloud-init on

/usr/sbin/chroot /mnt/ec2-fs /sbin/chkconfig cloud-init-user-scripts --add
/usr/sbin/chroot /mnt/ec2-fs /sbin/chkconfig --level 12345 cloud-init-user-scripts on

#### prevent java kernel pannic
echo "hwcap 1 nosegneg" > /mnt/ec2-fs/etc/ld.so.conf.d/libc6-xen.conf

##### configure network
##

cat <<EOF > /mnt/ec2-fs/etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE="eth0"
BOOTPROTO="dhcp"
IPV6INIT="yes"
MTU="1500"
NM_CONTROLLED="yes"
ONBOOT="yes"
TYPE="Ethernet"
EOF

cat <<EOF > /mnt/ec2-fs/etc/sysconfig/network
NETWORKING=YES
EOF

cat <<EOF > /mnt/ec2-fs/etc/resolv.conf
search ec2.internal
nameserver 172.16.0.23
EOF

# turn on networking in all runlevels
chroot /mnt/ec2-fs chkconfig --level 2345 network on

# configure ssh
echo "UseDNS  no" >> /mnt/ec2-fs/etc/ssh/sshd_config
echo "Banner /etc/issue.net" >> /mnt/ec2-fs/etc/ssh/sshd_config
echo "PermitRootLogin no" >> /mnt/ec2-fs/etc/ssh/sshd_config
# SSH login key based only
sed -i -e 's/^\(PasswordAuthentication\) yes/\1 no/' /etc/ssh/sshd_config

cat <<EOF > /mnt/ec2-fs/etc/issue
+=======================================================+
| Unauthorized access is strictly prohibited.           |
+=======================================================+
CentOS release 6.2 (Final)
Kernel \r on an \m

EOF

cat <<EOF > /mnt/ec2-fs/etc/issue.net

+=======================================================+
| Unauthorized access is strictly prohibited.           |
+=======================================================+

EOF

### configure SSH
########################################################
mkdir -p /mnt/ec2-fs/usr/local/sbin
cat <<EOF > /mnt/ec2-fs/usr/local/sbin/get-sshkey.sh
#!/bin/sh
if [ ! -d /home/foo/.ssh ] ;
then mkdir -p /root/.ssh
chmod 700 /root/.ssh
fi
# Fetch public key using HTTP
/usr/bin/curl -f http://169.254.169.254/1.0/meta-data/public-keys/0/openssh-key > /tmp/my-key
if [ $? -eq 0 ] ;
then
 cat /tmp/my-key > /home/foo/.ssh/authorized_keys
 chmod 600 /home/foo/.ssh/authorized_keys
 chown foo:foo /home/foo/.ssh/authorized_keys
 rm -f /tmp/my-key
else
  echo "FAILED TO CURL KEY" >> /var/log/startup-info
fi
echo "STARTUP == " >> /var/log/startup-info
/sbin/ifconfig -a >> /var/log/startup-info
/bin/df >> /var/log/startup-info
/sbin/ifconfig -a >> /var/log/startup-info
/bin/mount  >> /var/log/startup-info
echo "DONE"  >> /var/log/startup-info
EOF

# create foo user
chroot /mnt/ec2-fs adduser -d /home/foo -m foo
chroot /mnt/ec2-fs mkdir -p /home/foo/.ssh
chroot /mnt/ec2-fs chmod 0700 /home/foo/.ssh
chroot /mnt/ec2-fs chown foo:foo /home/foo/.ssh

chroot /mnt/ec2-fs adduser -d /home/application -m application
chroot /mnt/ec2-fs usermod -a -G application foo


# allow foo sudo access
cat <<EOF >> /mnt/ec2-fs/etc/sudoers
foo ALL = NOPASSWD: ALL
EOF

cat <<EOF >> /mnt/ec2-fs/etc/inittab
hvc0:2345:respawn:/sbin/getty 38400 hvc0
xvc0:2345:respawn:/sbin/getty 38400 xvc0
EOF

cat <<EOF >> /mnt/ec2-fs/etc/securetty
hvc0
xvc0
EOF

## startup scripts
chmod u+x /mnt/ec2-fs/usr/local/sbin/get-sshkey.sh

cat <<EOF >>  /mnt/ec2-fs/etc/rc.local
# FLUENT-specific
######

# grab ssh keys - use cloud-init instead
/usr/local/sbin/get-sshkey.sh

# todo - start chef-client
# todo

# Add ip address and hostname to /etc/hosts
hostname=$(/bin/hostname)
ipaddr=$(ifconfig eth0 | grep "inet addr:" | cut -d":" -f2 | cut -d" " -f1) 
echo "" >> /etc/hosts
echo "$ipaddr $hostname" >> /etc/hosts

EOF

# convenience
cat <<EOF >> /mnt/ec2-fs/etc/bashrc
# FLUENT
export JAVA_HOME=/usr/java/default
alias vi=vim
EOF

# todo - add chef

# configure ssh to start up
chroot /mnt/ec2-fs chkconfig --level 2345 sshd on

# remove unnecessary packages --- wtf, these aren't really all that optional after all...
# chroot /mnt/ec2-fs yum -y remove readahead
# chroot /mnt/ec2-fs yum -y remove plymouth plymouth-core-libs plymouth-scripts
# chroot /mnt/ec2-fs yum -y remove dbus
chroot /mnt/ec2-fs chkconfig acpid on

chroot /mnt/ec2-fs chkconfig --level 2345 kdump off
chroot /mnt/ec2-fs chkconfig --level 2345 cpuspeed off
# chroot /mnt/ec2-fs chkconfig --level 2345 acpid off
# chroot /mnt/ec2-fs chkconfig --level 2345 udev-post off
# chroot /mnt/ec2-fs chkconfig --level 2345 ip6tables off

# set up grub

cat <<EOL > /mnt/ec2-fs/boot/grub/grub.conf
# grub.conf generated by anaconda
#
# Note that you do not have to rerun grub after making changes to this file
# NOTICE:  You do not have a /boot partition.  This means that
#          all kernel and initrd paths are relative to /, eg.
#          root (hd0,0)
#          kernel /boot/vmlinuz-version ro root=/dev/xvda1
#          initrd /boot/initrd-[generic-]version.img
#boot=/dev/xvda
default=0
timeout=0
splashimage=(hd0,0)/grub/splash.xpm.gz
hiddenmenu
title CentOS
     root (hd0,0)
     kernel /vmlinuz ro root=/dev/mapper/foo_vol-root rd_LVM_LV=foo_vol/swap rd_LVM_LV=foo_vol/apps rd_LVM_LV=foo_vol/var rd_LVM_LV=foo_vol/root rd_NO_LUKS LANG=en_US.UTF-8 console=hvc0 KEYTABLE=us crashkernel=auto  
     initrd /initramfs
EOL

# symlink in relative fashion since this will be on / not /boot (separate partition from root!)
(cd /mnt/ec2-fs/boot/grub ; ln -s ./grub.conf menu.lst)
# ec2's pvgrub expects the grub.conf in /boot/grub/grub.conf
(cd /mnt/ec2-fs/boot ; ln -s . boot)


kern=`ls /mnt/ec2-fs/boot/vmlin*|awk -F/ '{print $NF}'`
ird=`ls /mnt/ec2-fs/boot/initramfs*.img|awk -F/ '{print $NF}'`

sed -ie "s/vmlinuz/$kern/" /mnt/ec2-fs/boot/grub/grub.conf
sed -ie "s/initramfs/$ird/" /mnt/ec2-fs/boot/grub/grub.conf

# update inittab
# echo "8:2345:respawn:/sbin/mingetty xvc0" >> /mnt/ec2-fs/etc/inittab
# securetty
# grep xvc0 /mnt/ec2-fs/etc/securetty || echo "xvc0" >> /mnt/ec2-fs/etc/securetty

# copy over cloud init
# cp /usr/bin/cloud-init* /mnt/ec2-fs/usr/bin/
# cp /etc/init.d/cloud-init* /mnt/ec2-fs/etc/init.d/

# disable selinux
cat <<EOF > /mnt/ec2-fs/etc/sysconfig/selinux
# This file controls the state of SELinux on the system.
# SELINUX= can take one of these three values:
#     enforcing - SELinux security policy is enforced.
#     permissive - SELinux prints warnings instead of enforcing.
#     disabled - No SELinux policy is loaded.
SELINUX=disabled
# SELINUXTYPE= can take one of these two values:
#     targeted - Targeted processes are protected,
#     mls - Multi Level Security protection.
SELINUXTYPE=targeted
EOF

echo "Installing chef..."
# setup ruby gems for chef
chroot /mnt/ec2-fs <<EOF
 cd /tmp
 curl -O http://production.cf.rubygems.org/rubygems/rubygems-1.8.10.tgz
 tar zxf rubygems-1.8.10.tgz
 cd rubygems-1.8.10
 ruby setup.rb --no-format-executable
EOF

mkdir /mnt/ec2-fs/etc/chef

cp /tmp/setup_data.sh /mnt/ec2-fs/usr/bin
cat /tmp/rc.local >> /mnt/ec2-fs/etc/rc.local


# cleanup
yum -c $IMAGE_DIR/yum-xen.conf --installroot=/mnt/ec2-fs clean all

sync
sleep 60
sync
sleep 60
umount /mnt/ec2-fs/data
umount /mnt/ec2-fs/apps
umount /mnt/ec2-fs/var
umount /mnt/ec2-fs/dev/shm
umount /mnt/ec2-fs/dev/pts
umount /mnt/ec2-fs/sys
umount /mnt/ec2-fs/proc/sys/fs/binfmt_misc
umount /mnt/ec2-fs/proc
umount /mnt/ec2-fs/dev
umount /mnt/ec2-fs/boot
umount /mnt/ec2-fs

