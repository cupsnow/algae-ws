#!/bin/sh

. /etc/init.d/func

_pri_tag="mdev-default"

log_d "$0 $*"

log_file="/var/run/mdev-default.log"

log_f "$log_file"
log_f "$log_file" "$0 $*"
log_f "$log_file" "env: `env`"
