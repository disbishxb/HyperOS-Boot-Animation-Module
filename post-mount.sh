#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/bin/common.sh"

ensure_runtime_dirs

err_log="$LOG_DIR/post-mount.log"

prepare_payload || echo "[$(date '+%Y-%m-%d %H:%M:%S')] prepare_payload failed" >>"$err_log"
ensure_overlay_tree || echo "[$(date '+%Y-%m-%d %H:%M:%S')] ensure_overlay_tree failed" >>"$err_log"
deploy_bind_mounts || echo "[$(date '+%Y-%m-%d %H:%M:%S')] deploy_bind_mounts failed" >>"$err_log"

record_status "post-mount"