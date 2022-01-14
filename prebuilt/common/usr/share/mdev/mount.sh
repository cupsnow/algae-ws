#!/bin/sh

LogFile=/var/run/mdev-mount.log

log_file () {
  local eno=$?
  if [ -z "$1" ]; then
    echo "" >> $LogFile
    date >> $LogFile
  else
    echo "$*" >> $LogFile
  fi
  return $eno
}

log_file

log_file "$0 $*"
log_file "env:"
log_file `env`

case "$ACTION" in
add)
  [ -z "${MDEV}" ] && exit 1
  cat /proc/mounts | awk '{print $1}' | grep "^/dev/${MDEV}$" || {
    [ -d "/media/${MDEV}" ] || mkdir -p /media/${MDEV}
	mount -o sync /dev/${MDEV} /media/${MDEV} || {
		log_e "Failed mount /dev/${MDEV} to /media/${MDEV}"
		exit 1
	}
  }
  exit 0
  ;;
remove)
  [ -z "${MDEV}" ] && exit 1
  for i in `cat /proc/mounts | grep "${MDEV}" | cut -f 2 -d " "`; do
    umount $i
  done
  [ -d /media/${MDEV} ] && rm -rf /media/${MDEV}
  exit 0
  ;;
esac
