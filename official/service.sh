#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/bin/common.sh"

ensure_runtime_dirs

sleep 15
prepare_payload
deploy_bind_mounts
record_status "service"

# 更多播放功能
apply_play_mode