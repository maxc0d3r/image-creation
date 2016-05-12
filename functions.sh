#This script contains various functions which are going to be used in ami creation script

usage() {
        echo "Usage: create_image [-t!--type ami type]"
        exit 0
}

cleanup() {
  rm -f /tmp/fstab
  echo "Cleanup not yet implemented"
  # losetup -d /dev/loop0

}

check_result() {
 if [ $? -ne 0 ]; then
  echo "Failed"
  cleanup
  exit 1
 fi
}
