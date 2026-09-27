#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/bin/common.sh" 2>/dev/null

# 先解除所有 bind mount，避免卸载后开机动画指向已删除文件
if command -v device_target_paths >/dev/null 2>&1; then
  for target_path in $(device_target_paths 2>/dev/null); do
    [ -n "$target_path" ] || continue
    if grep -F " $target_path " /proc/self/mountinfo >/dev/null 2>&1; then
      umount "$target_path" 2>/dev/null
    fi
  done
fi

# 删除非模块目录（原厂备份 + 配置 + 状态）
rm -rf /data/adb/hyperosbootanim

echo "hyperosbootanim uninstall: cleanup done."
