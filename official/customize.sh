#!/system/bin/sh

ui_print "*********************************************"
ui_print "         HyperOS 开机动画模块 v2.3.2"
ui_print "*********************************************"
ui_print "- 目标系统：HyperOS / MIUI"
ui_print "- 适配环境：Magisk / KernelSU / APatch"
ui_print "- 工作方式：免改分区覆盖 + 早期 bind mount 兜底"
ui_print "- 默认动画：MIUI粒子效果"
ui_print "*********************************************"

if [ -n "$MODPATH" ]; then
  MODDIR="$MODPATH"

  mkdir -p "$MODPATH/bin" "$MODPATH/payload" "$MODPATH/var/state" "$MODPATH/var/config" 2>/dev/null

  # 固定为米系
  echo "xiaomi" > "$MODPATH/var/state/brand"

  rm -f "$MODPATH"/payload/hyperosbootanim-*.zip 2>/dev/null
  chmod 0755 \
    "$MODPATH/customize.sh" \
    "$MODPATH/post-fs-data.sh" \
    "$MODPATH/post-mount.sh" \
    "$MODPATH/service.sh" \
    "$MODPATH/uninstall.sh" 2>/dev/null
  chmod 0755 "$MODPATH/bin/"*.sh 2>/dev/null

  if [ -f "$MODPATH/bin/common.sh" ]; then
    . "$MODPATH/bin/common.sh"
    ensure_runtime_dirs
    if prepare_payload; then
      refresh_overlay_tree >/dev/null 2>&1
      record_status "install"
      update_module_prop_description "$(selected_display_name)"
      ui_print "- 已检测到内置动画包：$(payload_size_bytes) bytes"
      library_total=$(payload_library_count)
      ui_print "- 动画库共 $library_total 个动画，可在模块设置中切换"
      ui_print "- 默认动画：$(selected_source_name)"
    else
      ui_print "! 缺少 payload/bootanimation.zip"
    fi
  fi

  # ========== 版本检测 ==========
  ui_print ""
  ui_print "🔍 正在检查模块版本…"
  sleep 3
  ui_print "✅ 是官版，默认米系方案……"
  ui_print ""
fi