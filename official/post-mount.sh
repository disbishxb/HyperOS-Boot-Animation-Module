#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/bin/common.sh"

ensure_runtime_dirs

prepare_payload
ensure_overlay_tree
deploy_bind_mounts
record_status "post-mount"