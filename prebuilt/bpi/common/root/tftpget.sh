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

prebuilt_common_dir="algae-ws/algae/prebuilt/common"
prebuilt_algae_dir="algae-ws/algae/prebuilt/algae/common"

for i in "$@"; do
  case $i in
  $(basename $0))
    tftpget_x "algae-ws/algae/builder/$i"
    ;;
  admin)
    admin_rel_builddir="algae-ws/build/admin-aarch64"
    admin_dbg_builddir="algae-ws/algae/build/admin-aarch64"

    tftpget_x "${admin_rel_builddir}/.libs/libadmin.so.0.0.0" \
      "/lib/libadmin.so.0.0.0" || \
      tftpget_x "${admin_dbg_builddir}/.libs/libadmin.so.0.0.0" \
        "/lib/libadmin.so.0.0.0" 
    tftpget_n "${admin_rel_builddir}/.libs/libadmin.so.0" \
      "/lib/libadmin.so.0" || \
      tftpget_n "${admin_dbg_builddir}/.libs/libadmin.so.0" \
        "/lib/libadmin.so.0" 
    tftpget_n "${admin_rel_builddir}/.libs/libadmin.so" \
      "/lib/libadmin.so" || \
      tftpget_n "${admin_dbg_builddir}/.libs/libadmin.so" \
        "/lib/libadmin.so" 
    
    tftpget_x "${admin_rel_builddir}/.libs/admin" \
      "/bin/admin" || \
      tftpget_x "${admin_dbg_builddir}/.libs/admin" \
        "/bin/admin" 
        
    tftpget_x "${admin_rel_builddir}/.libs/test1" || \
      tftpget_x "${admin_dbg_builddir}/.libs/test1"

    tftpget_n "algae-ws/algae/package/admin/test/admin2.html" \
      "/var/www/admin2.html"
    ;;
  www)
    tftpget_n "${prebuilt_algae_dir}/var/www/admin.html" \
      "/var/www/admin.html"
    tftpget_n "${prebuilt_algae_dir}/etc/lighttpd.conf" \
      "/etc/lighttpd.conf"
    tftpget_x "${prebuilt_algae_dir}/etc/init.d/lighttpd-initd" \
      "/etc/init.d/lighttpd-initd"
    ;;
  ifplugd|zcip|udhcpc|mdev)
    tftpget_x "${prebuilt_algae_dir}/etc/ifplugd/ifplugd.action" \
      "/etc/ifplugd/ifplugd.action"
    tftpget_x "${prebuilt_common_dir}/usr/share/zcip/default.script" \
      "/usr/share/zcip/default.script"
    tftpget_x "${prebuilt_common_dir}/sbin/zcipwrapper" \
      "/sbin/zcipwrapper"
    tftpget_x "${prebuilt_common_dir}/usr/share/udhcpc/default.script" \
      "/usr/share/udhcpc/default.script"
    tftpget_x "${prebuilt_common_dir}/etc/init.d/mdev-initd" \
      "/etc/init.d/mdev-initd"
    tftpget_n "${prebuilt_common_dir}/etc/mdev.conf" \
      "/etc/mdev.conf"
    for i in mount.sh eth.sh default.sh; do
      tftpget_x "${prebuilt_common_dir}/usr/share/mdev/$i" \
        "/usr/share/mdev/$i"
    done
    ;;
  wpasup)
    tftpget_x "${prebuilt_common_dir}/sbin/wpasup" \
      "/sbin/wpasup"
    tftpget_n "algae-ws/algae/builder/wpasup.conf"
    ;;
  cryptodev)
    tftpget_n "algae-ws/build/cryptodev-aarch64/cryptodev.ko" \
      "/lib/modules/$(uname -r)/extra/cryptodev.ko"
    ;;
  *)
    tftpget_x $i
    ;;
  esac
done

[ -n "$_pri_listok" ] && echo && echo "Ok:" && ls -l $_pri_listok
[ -n "$_pri_listfailed" ] || exit 0
echo && echo "Failed:" && ls -l $_pri_listfailed

