#!/bin/sh

. /sbin/func.sh

_pri_ip="192.168.12.18"
_pri_listok=""
_pri_listfailed=""

do_cmd () {
  echo "Execute: $*"
  "$@"
}

tftpput_n () {
  [ -n "$1" ] || return 0
  _lo_cwd="$(pwd)"
  _lo_destdir="$(dirname "$1")"
  _lo_fn="$(basename "$1")"
  do_cmd cd "$_lo_destdir"
  if ! do_cmd tftp -b 50000 -p -l "$_lo_fn" $_pri_ip; then
    _pri_listfailed="$_pri_listfailed $_lo_fn"
    do_cmd cd "$_lo_cwd"
    return 1
  fi
  _pri_listok="$_pri_listok $_lo_fn"
  do_cmd cd "$_lo_cwd"
  return 0
}

tftpget_n () {
  if ! do_cmd tftp -b 50000 -g -r $1 ${2:+-l $2} $_pri_ip; then
    _pri_listfailed="$_pri_listfailed $(basename "$1")"
    return 1
  fi
  _lo_tgt="${2:-$(basename "$1")}"
  _pri_listok="$_pri_listok $_lo_tgt"
  return 0
}

tftpget_x () {
  _lo_tgt="${2:-$(basename "$1")}"
  tftpget_n "$@" && do_cmd chmod +x "$_lo_tgt"
}

_pri_opts="$(getopt -l "help,addr:,debug" -- ha:d "$@")" || exit 1

eval set -- "$_pri_opts"

while [ -n "$1" ]; do
  case "$1" in
  -h|--help)
    shift
    ;;
  -a|--addr)
    _pri_ip="$2"
    shift 2
    ;;
  -g|--debug)
    _pri_dbgobj=1
    shift
    ;;
  --)
    shift
    break
    ;;
  esac
done


if [ "$1" = "tftpput" ] || [ "$1" = "put" ] || [ "$1" = "-p" ]; then
  shift
  for i in "$@"; do
    tftpput_n "$i"
  done
  exit
fi

for i in "$@"; do
  case $i in
  $(basename $0)|tftpget.sh|func.sh|wpasup)
    tftpget_x "algae-ws/algae/prebuilt/bpi/common/root/tftpget.sh"
    tftpget_x "algae-ws/algae/prebuilt/common/sbin/func.sh" /sbin/func.sh
    tftpget_x "algae-ws/algae/prebuilt/common/sbin/wpasup" /sbin/wpasup
    ;;
  openocd)
    tftpget_n "algae-ws/algae/package/mkr4000/openocd/bpi-openocd-interface.cfg"
    tftpget_n "algae-ws/algae/package/mkr4000/openocd/mkr4000-target.cfg"
    tftpget_n "algae-ws/algae/package/mkr4000/openocd/mkr4000-flash-bootloader.cfg"
    tftpget_n "algae-ws/algae/package/mkr4000/openocd/samd21_sam_ba_arduino_mkrvidor4000.bin"
    ;;
  *)
    tftpget_x $i
    ;;
  esac
done

[ -n "$_pri_listok" ] && echo && echo "Ok:" && ls -l $_pri_listok
[ -n "$_pri_listfailed" ] || exit 0
echo && echo "Failed:" && ls -l $_pri_listfailed

