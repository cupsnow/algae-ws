#!/bin/sh

func_involved="$(( $func_involved + 1 ))"
[ $func_involved -le 1 ] || echo "func_involved: $func_involved"

persist_cfg="/etc"
accname_cfg="${persist_cfg}/acc_name"
hostname_cfg="${persist_cfg}/hostname"
wpasup_cfg="${persist_cfg}/wpa_supplicant.conf"
eth_cfg="${persist_cfg}/eth.conf"
wlan_cfg="${persist_cfg}/wlan.conf"
macaddr_cfg="${persist_cfg}/macaddr.conf"
spkcal_cfg="${persist_cfg}/spklatency"
wol_cfg="${persist_cfg}/wol.conf"
snhash_cfg="${persist_cfg}/snhash.conf"
spkcal_raw="/var/run/spklatency"
led_cfg="/etc/led.conf"
oob_cfg="/etc/outofbox"
promisc_cfg="/etc/promisc"
resolv_cfg="/var/run/udhcpc/resolv.conf"
wfa_cfg="/etc/wfa.conf"

sd_brcm_vid=0x02d0
sd_brcm43455_did=0xa9bf
sd_brcm43438_did=0xa9a6

sd_rtl_vid=0x024c
sd_rtl8821_did=0xc821

usb_asix_vid=0b95
usb_ax88772_did=772b

ts_dt () {
  date "+%y-%m-%d %H:%M:%S"
}

ts_dt2 () {
  date +%y%m%d%H%M%S
}

log_d () {
  logger ${_pri_tag:+-t "$_pri_tag"} -p user.debug "$*"
}

log_sd () {
  echo "[debug]${_pri_tag:+[$_pri_tag]} $*"
  log_d "$*"
}

log_i () {
  logger ${_pri_tag:+-t "$_pri_tag"} -p user.info "$*"
}

log_e () {
  logger ${_pri_tag:+-t "$_pri_tag"} -p user.err "$*"
}

log_se () {
  logger -s ${_pri_tag:+-t "$_pri_tag"} -p user.err "$*"
}

log_f () {
  [ -n "$1" ] || return
  local log_file="$1"
  shift
  if [ -z "$*" ]; then
    echo "" >> $log_file
    date >> $log_file
    return
  fi
  local ts="$(date "+%F %T")"
  echo "$ts $*" >> $log_file
}

cmd_run () {
  log_d "Execute: $*"
  $@
}

positive1 () {
  case "$1" in
  1|on|y|yes|true|positive)
    echo 1
    return 0
    ;;
  0|off|n|no|false|negative)
    echo 0
    return 0
    ;;
  esac
  return 1
}

as_num () {
  _pri_num=`printf "%d" $1 2>/dev/null` && echo "$_pri_num"
}

# get_inient1 "/etc/outofbox" "bct"
get_inient1 () {
  [ $# -ge 2 ] && [ -f "$1" ] || return 1
  local ent1="$(sed -E -n -e "s/^\s*$2\s*=\s*(.*)/\1/p" $1 2>/dev/null)"
  [ -n "$ent1" ] && echo $ent1
}

rm_inient1 () {
  sed -E -i -e "/^\s*$2\s*=.*/d" $1 2>/dev/null
}

file_size () {
  [ -n "$1" ] || return 1
  local msg=$(wc -c $1 2>/dev/null) || return 1
  local sz=$(echo $msg | awk '{print $1;}')
  local sz=$(as_num $sz)
  [ -n "$sz" ] && echo $sz
}

macaddr_gen () {
  local nx=${1:-6}
  local macaddr=
  local idx=0
  for nv in `od -An -tx1 -N${nx} /dev/urandom`; do
    [ $idx -lt 1 ] && macaddr="${macaddr}${nv}" || macaddr="${macaddr}:${nv}"
    idx=$(( $idx + 1 ))
  done
  echo "$macaddr"
}

ifce_list2 () {
  local ifce=$(ip l 2>/dev/null | sed -n "s/^[0-9]*:\s\(${1}[^:]*\):\s*<.*${2}.*>.*/\1/p")
  [ -n "$ifce" ] && echo $ifce
}

ifce_link_up () {
  [ "`cat /sys/class/net/${1}/carrier 2>/dev/null`" = "1" ]
}

# phy=`iw_phy` && echo "Wifi deivce: $phy"
iw_phy () {
  local phy=$(iw dev 2>/dev/null | sed -n "s/^phy#\(\d*\)/phy\1/p")
  [ -n "$phy" ] && echo $phy
}

iw_dev () {
  local dev=$(iw dev 2>/dev/null | sed -n "s/^\s*Interface\s*\(.*\)/\1/p")
  [ -n "$dev" ] && echo $dev
}

wpa_ssid () {
 local ssid="$(sed -n 's/^\s*[^#]\s*ssid\s*=\s*["]\(.*\)["]/\1/p' $wpasup_cfg 2>/dev/null)"
  [ -n "$ssid" ] && echo $ssid
}

wphy_wait () {
  local ct=${1:-3}
  local wphy=
  while ! wphy="$(iw_phy)" && [ $ct -gt 0 ]; do
    log_sd "wait wphy in $ct"
    sleep 1
    ct="$(( $ct - 1 ))"
  done
  [ -n "$wphy" ] && echo $wphy
}

do_insmod () {
  [ -n "$1" ] || { log_e "do_insmod invalid parameter"; return 1; }
  local modname=$(basename $1)
  modname="$(echo ${modname%.*} | tr '-' '_')"
  if [ -e "/sys/module/${modname}" ]; then
    log_d "module already loaded: ${modname}, skip $*"
  elif insmod $*; then
    log_d "module loaded: $*"
  else
    return 1
  fi
}

get_led () {
  cat $1 | sed -n -e 's/.*"led"\s*\:\s*\[\(.*\)\].*/\1/' \
    -e 's/.*\s*"color"\s*:\s*"white".*"pin"\s*:\s*\([0-9]*\).*/\1/p'
}

adk_paired () {
  [ -f "/root/.HomeKitStore/A0.00" ]
}

find_usbdev () {
  local dev_vid=$(echo ${1:-$_pri_vid} | tr [:lower:] [:upper:])
  dev_vid=${dev_vid#0X}
  local dev_pid=$(echo ${2:-$_pri_pid} | tr [:lower:] [:upper:])
  dev_pid=${dev_pid#0X}

  # log_d "${dev_vid}:${dev_pid}"

  for i in $(find -L /sys/bus/usb/devices -maxdepth 2 -iname idVendor -exec dirname '{}' \;); do
    [ -e "${i}/idProduct" ] || continue

    iter_vid=$(cat ${i}/idVendor | tr [:lower:] [:upper:])
    iter_vid=${iter_vid#0X}
    iter_pid=$(cat ${i}/idProduct | tr [:lower:] [:upper:])
    iter_pid=${iter_pid#0X}

    # log_d "test $iter_vid:$iter_pid"

    [ "$iter_vid" = "$dev_vid" ] || continue
    [ -z "$dev_pid" ] || [ "$iter_pid" = "$dev_pid" ] || continue

    echo "${i}"
    return 0
  done
  return 1
}

find_sddev () {
  local dev_vid=$(echo ${1:-$_pri_vid} | tr [:lower:] [:upper:])
  dev_vid=${dev_vid#0X}
  local dev_did=$(echo ${2:-$_pri_did} | tr [:lower:] [:upper:])
  dev_did=${dev_did#0X}

  # log_d "${dev_vid}:${dev_did}"

  local iter_vid iter_did
  for i in $(find -L /sys/bus/sdio/devices -maxdepth 2 -iname vendor -exec dirname '{}' \; 2>/dev/null); do
    [ -e "${i}/device" ] || continue

    iter_vid=$(cat ${i}/vendor | tr [:lower:] [:upper:])
    iter_vid=${iter_vid#0X}
    iter_did=$(cat ${i}/device | tr [:lower:] [:upper:])
    iter_did=${iter_did#0X}

    # log_d "test $iter_vid:$iter_did"

    [ "$iter_vid" = "$dev_vid" ] || continue
    [ -z "$dev_did" ] || [ "$iter_did" = "$dev_did" ] || continue

    echo "${i}"
    return 0
  done
  return 1
}

find_mtd () {
# cat /proc/mtd
# dev:    size   erasesize  name
# mtd3: 00040000 00020000 "pref"
  local dev=$(cat /proc/mtd | sed -n "s/^mtd\([0-9][0-9]*\)\:\s\s*.*\"$1\"/\1/p")
  [ -n "$dev" ] && echo $dev
}

find_ubi () {
# /sys/class/ubi/ubi0/mtd_num:10
  local dev="$(grep -iwR ${1} /sys/class/ubi/ubi[0-9]/mtd_num | \
      sed -n -E "s/\/sys\/class\/ubi\/ubi(.*)\/mtd_num:.*/\1/p")"
  [ -n "$dev" ] && echo $dev
}

find_mount () {
  # root@Eve_Play: ~ # cat /proc/mounts
  # ubi0:rootfs / ubifs rw,sync,relatime,assert=read-only,ubi=0,vol=0 0 0
  # devtmpfs /dev devtmpfs rw,relatime,size=51140k,nr_inodes=12785,mode=755 0 0
  # none /proc proc rw,relatime 0 0
  # none /sys sysfs rw,relatime 0 0
  # none /dev/pts devpts rw,relatime,mode=600,ptmxmode=000 0 0
  # none /dev/mqueue mqueue rw,relatime 0 0
  # none /var/run tmpfs rw,relatime,size=10240k 0 0
  # none /var/lock tmpfs rw,relatime,size=10240k 0 0
  # none /media tmpfs rw,relatime,size=40960k 0 0
  # none /sys/kernel/debug debugfs rw,relatime 0 0
  # /dev/ubi1_0 /mnt/cfg ubifs rw,relatime,assert=read-only,ubi=1,vol=0 0 0
  _pri_for_iter=0
  while read _pri_line; do
    # [ $_pri_for_iter -lt $_pri_for_count ] || break
    # echo "[$_pri_for_iter]$_pri_line"

    read _pri_dev _pri_dir _pri_fs _dommy <<-EOM
$(echo $_pri_line)
EOM
    log_d "[#$_pri_for_iter] $_pri_dev, $_pri_dir, $_pri_fs"

    local _pri_ng=
    [ -n "$_pri_ng" ] || [ "$1" = "*" ] || [ "$1" = "$_pri_dev" ] || _pri_ng=n
    [ -n "$_pri_ng" ] || [ -z "$2" ] || [ "$2" = "*" ] || [ "$2" = "$_pri_dir" ] || _pri_ng=n
    [ -n "$_pri_ng" ] || [ -z "$3" ] || [ "$3" = "*" ] || [ "$3" = "$_pri_fs" ] || _pri_ng=n
    [ -z "$_pri_ng" ] && { echo $_pri_line; return 0; }

    _pri_for_iter="$(( $_pri_for_iter + 1 ))"
  done <<-EOR
$(cat /proc/mounts)
EOR
  return 1
}

# state=`wpa_state` || echo "WPA not ready"
wpa_state () {
  local st=$(wpa_cli ${1:+-i${1}} status 2>/dev/null | sed -n "s/^wpa_state\s*=\s*\(.*\)/\1/p")
  echo $st
  [ "$st" == "COMPLETED" ]
}

wpa_wait () {
  local ct=${1:-3}
  local wpast=
  while ! wpast="$(wpa_state)" && [ $ct -gt 0 ]; do
    log_d "wait wpa complete in $ct"
    sleep 1
    ct="$(( $ct - 1 ))"
  done
  log_d "wpa_state: $wpast"
  echo $wpast
  [ "$wpast" == "COMPLETED" ]
}

# state=`hostapd_state` && [ "$state" == "ENABLED" ] && echo "hostapd ready"
hostapd_state () {
  wpa_cli -p /var/run/hostapd -i wlan0 status 2>/dev/null | sed -n "s/^state\s*=\s*\(.*\)/\1/p"
}

ifce_list () {
  ifce_list2 "" "$@"
}

mifce_list () {
  ifce_list2 "" "MULTICAST"
}

ip_list () {
  [ -n "$1" ] || return
  for ifce in $*; do
    ip a show dev $ifce 2>/dev/null | sed -n "s/^\s*inet\s\s*\([.0-9]*\).*/\1/p"
  done
}

dns_list () {
  sed -n "s/^\s*nameserver\s\s*\([^\s]*\).*/\1/p" "$@"
}

countdown () {
  local _pri_ct=${1:-3}
  while [ $_pri_ct -gt 0 ]; do
    [ -z "$2" ] || eval "$2 $_pri_ct"
    sleep 1
    _pri_ct=$(( $_pri_ct - 1 ))
  done
}

add_resolv_dns () {
  [ $# -eq 2 ] || return 1
  local resolv=$1
  local dns=$2

  [ -d `dirname $resolv` ] || mkdir -p `dirname $resolv`
  [ -e $resolv ] || touch $resolv

  for iter in `dns_list $resolv`; do
    [ "$iter" = "$dns" ] && return 2
  done
  echo "nameserver $dns" >> $resolv
}

ip_del_ifce () {
  [ -n "$1" ] || return
  for ifce in $*; do
    ip_list $ifce | while read ip; do
      log_d "Execute: ip a del $ip dev $ifce"
      ip a del $ip dev $ifce
    done
  done
}

route_del_ifce () {
  [ -n "$1" ] || return
  for ifce in $*; do
    ip r list dev $ifce 2>/dev/null | \
        sed -n "s/\s*\(.*\s\s*dev\s\s*$ifce\)\s.*/\1/p" | \
        while read rul; do
      log_d "Execute: ip r del $rul"
      ip r del $rul
    done
  done
}

# kill_prog "wpa_supplicant|udhcpc"
# return true when all killed
kill_prog () {
  local _pri_pat="$@"
  for _pri_pid in `pgrep -x "$_pri_pat"`; do
    kill $_pri_pid 2>/dev/null
  done
  pgrep -x "$_pri_pat" &>/dev/null || return 0
  local _pri_ct=5
  while [ $_pri_ct -gt 0 ]; do
    log_d "Checking remaining process (countdown $_pri_ct)"
    sleep 0.3
    pgrep -x "$_pri_pat" &>/dev/null || return 0
    _pri_ct=$(( $_pri_ct - 1 ))
  done
  for _pri_pid in `pgrep -x "$_pri_pat"`; do
    log_d "Terminate `cat /proc/$_pri_pid/cmdline 2>/ev/null | xargs -0`"
    kill -9 $_pri_pid 2>/dev/null
  done
  pgrep -x "$_pri_pat" &>/dev/null || return 0
  return 1
}

# daemon [start|stop] <PROG> [ARGS...]
# Start PROG when not running or kill all instance
daemon () {
  case "$1" in
  "start")
    shift
    pgrep -x "$1" || $* &
    ;;
  "stop")
    shift
    pgrep -x "$1" | while read _pri_pid; do
      kill $_pri_pid
    done
    ;;
  "restart")
    shift
    pgrep -x "$1" | while read _pri_pid; do
      kill $_pri_pid
    done
    for i in `seq 10`; do
      pgrep -x "$1" &>/dev/null || break
      sleep 0.3
    done
    pgrep -x "$1" || $* &
    ;;
  *)
    ;;
  esac
}
