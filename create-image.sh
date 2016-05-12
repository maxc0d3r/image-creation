#!/bin/bash
# To be executed on a box in the cloud with EC2 tools installed -
########################################################

#
# ideas - pass in ebs storage volumes to add to the /apps directory automagically?
# todos 
#    - make image bigger than 20gb by default
#

source ./configure.sh
source ./functions.sh

#Few variables
TYPE="small"
declare -a VOLUME_ID
VDEV=/dev/sdf
FSTYPE=ext4

while [ "$1" != "" ]; do
    case $1 in
    -t | --type )	    	shift
			    			TYPE=$1
			    			;;
  	-h | --help )           usage                             
                            ;;
    * )                     usage
							;;
   esac
   shift
done

case $TYPE in 
	"small")
		ROOT_SIZE=92
		SWAP_SIZE=2G
		DATA_SIZE=50G
		;;
	"medium")
		ROOT_SIZE=344
		SWAP_SIZE=4G
		DATA_SIZE=500G
		;;
esac

echo "Mount point - $VDEV. Image Size: $ROOT_SIZE. Type: $TYPE"
echo "If this is not right, hit CTRL-C in the next 5 seconds"
sleep 5
echo "Starting installation"

# create and attach new volume as /dev/$VDEV
export EC2_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
export INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
if [ -z "$INSTANCE_ID" ]; then
	echo "Cannot get Instance Id"
	exit 1
fi
echo "Creating EC2 volume"
VOLUME_ID=$(ec2-create-volume -s $ROOT_SIZE -z $EC2_REGION | cut -f2)
echo $VOLUME_ID > /tmp/script_out
check_result
echo "Created volume $VOLUME_ID. Now attaching to instance  $INSTANCE_ID"
ec2-attach-volume $VOLUME_ID -i  $INSTANCE_ID -d $VDEV
check_result

sleep 60

# create partition table with /boot=1 GB and remainder assigned to LVM
echo "Creating partition table on $VDEV"
fdisk $VDEV << EOF
n
p
1
1
+1G
n
p
2
n
p
2	


t
2
8e
w
EOF

sleep 2
echo "Created partition table: "
fdisk -l $VDEV
sleep 2

### Format the partition and label, then set fsck never to be run on boot
mkfs -t $FSTYPE -L 'boot' ${VDEV}1
check_result
tune2fs -c 0 -i 0 ${VDEV}1
check_result

sleep 2

# initialize LVM
echo "Setting up LVM"
# create physical volume
pvcreate ${VDEV}2
check_result
# create a volume group and add the just created physical volume to it
vgcreate foo_vol ${VDEV}2

# now create a few logical volumes in that group to mount the file systems in. Min is 20GB!!
##    - ROOT FS: 
##	  - SWAP:    
##	  - VAR:     
##	  - APPS:   
##	  - DATA:
lvcreate -ay --size 10G --name root foo_vol
check_result

lvcreate -ay --size $SWAP_SIZE --name swap foo_vol
check_result

lvcreate -ay --size 18G --name var foo_vol
check_result

lvcreate -ay --size 10G --name apps foo_vol
check_result

lvcreate -ay --size $DATA_SIZE --name data foo_vol
check_result

sleep 5
# make file systems
echo "Making filesystems"
sleep 5

for i in root var apps data; do 
	mkfs -t $FSTYPE -L $i /dev/foo_vol/$i
	check_result
	tune2fs -c 0 -i 0 /dev/foo_vol/$i
	check_result
done

echo "Making swap space"
mkswap -L 'ebs-swap' /dev/foo_vol/swap

# mount the new root drives
mkdir -p /mnt/ec2-fs
mount /dev/foo_vol/root /mnt/ec2-fs

mkdir -p /mnt/ec2-fs/boot
mount ${VDEV}1 /mnt/ec2-fs/boot

mkdir -p /mnt/ec2-fs/var
mount /dev/foo_vol/var /mnt/ec2-fs/var

mkdir -p /mnt/ec2-fs/apps
mount /dev/foo_vol/apps /mnt/ec2-fs/apps

mkdir -p /mnt/ec2-fs/data
mount /dev/foo_vol/data /mnt/ec2-fs/data

#Copy fstab
cat << EOF > /tmp/fstab
/dev/mapper/foo_vol-root          /          ext4    defaults,relatime 1 1
/dev/mapper/foo_vol-var           /var       ext4    defaults,relatime 1 2
/dev/mapper/foo_vol-apps          /apps      xfs     defaults,noatime  0 0
/dev/mapper/foo_vol-data          /data      xfs     defaults,noatime  0 0
LABEL=boot               /boot                  ext4      defaults 1 2
tmpfs                   /dev/shm                tmpfs   defaults        0 0
devpts                  /dev/pts                devpts  gid=5,mode=620  0 0
sysfs                   /sys                    sysfs   defaults        0 0
proc                    /proc                   proc    defaults        0 0
/dev/mapper/foo_vol-swap          none                    swap    sw              0  0
/dev/sdb   /media/ephemeral0   auto   defaults,nofail,comment=cloudconfig   0   2
EOF

chmod 755 /tmp/setup_data.sh

# run the installer
echo "About to install CentOS in image. Hit CTRL-C within 5 secs to abort"
sleep 5
echo "Starting installation"
./install-centos.sh
check_result

echo "Detaching volume"
counter=0
ec2-detach-volume ${VOLUME_ID}
check_result

echo "Creating snapshot"
SNAPSHOT_ID=$(ec2-create-snapshot -d "os-snapshot" $VOLUME_ID | cut -f2)
check_result
echo "Snapshot ${SNAPSHOT_ID}"
echo ${SNAPSHOT_ID} >> /tmp/script_out


sleep 300
AKI=aki-8e5ea7e7

echo "Registering AMI"
ec2-register -b "/dev/sda=${SNAPSHOT_ID}::true" -b "/dev/sdb=ephemeral0" -b -n "Foo CentOS $TYPE - ${SNAPSHOT_ID}" -a x86_64 --kernel $AKI

cleanup
echo "Done"
