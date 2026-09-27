#!/system/bin/sh

ui_print "*********************************************"
ui_print "         HyperOS 开机动画模块 v2.4.0"
ui_print "*********************************************"
ui_print "- 目标系统：HyperOS / ColorOS / OxygenOS"
ui_print "- 适配环境：Magisk / KernelSU / APatch"
ui_print "- 工作方式：免改分区覆盖 + 早期 bind mount 兜底"
ui_print "- 日志目录：/data/adb/modules/hyperosbootanim/var/logs"
ui_print "*********************************************"

# ========== 旧版检测 ==========
if [ -d "/data/adb/modules/colorosbootanim" ]; then
  ui_print "! 检测到旧版 ColorOS 模块 (colorosbootanim)"
  ui_print "! 请先在模块管理器中卸载旧版，重启后再安装本模块"
  ui_print "! 安装已中止"
  abort "请卸载旧版后重启"
fi

# ========== 三星设备检测 ==========
brand=$(getprop ro.product.brand 2>/dev/null | tr '[:upper:]' '[:lower:]')
manufacturer=$(getprop ro.product.manufacturer 2>/dev/null | tr '[:upper:]' '[:lower:]')

is_samsung=0
case "$brand" in
  samsung|*samsung*) is_samsung=1 ;;
esac
case "$manufacturer" in
  samsung|*samsung*) is_samsung=1 ;;
esac

if [ "$is_samsung" = "1" ]; then
  ui_print "*********************************************"
  ui_print "! 检测到三星（Samsung）设备"
  ui_print "! 本模块基于 MIUI / HyperOS / ColorOS / OxygenOS 开机动画机制"
  ui_print "! 三星使用完全不同的 bootanimation 格式与路径"
  ui_print "! 在三星上【绝对无效】，甚至可能引起无法开机"
  ui_print "! 安装已中止"
  ui_print "*********************************************"
  abort "三星设备不支持，安装已取消"
fi

if [ -n "$MODPATH" ]; then
  MODDIR="$MODPATH"

  mkdir -p "$MODPATH/bin" "$MODPATH/payload" "$MODPATH/payload/animations" "$MODPATH/payload/backups" \
           "$MODPATH/var/logs" "$MODPATH/var/state" "$MODPATH/var/tmp" 2>/dev/null
  touch "$MODPATH/payload/.keep" \
        "$MODPATH/payload/animations/.keep" \
        "$MODPATH/payload/backups/.keep" \
        "$MODPATH/payload/backups/index.txt" \
        "$MODPATH/var/logs/.keep" \
        "$MODPATH/var/state/.keep" \
        "$MODPATH/var/tmp/.keep" 2>/dev/null

  # ========== 品牌写入 ==========
  if [ -f "$MODPATH/payload/.brand" ]; then
    cp -f "$MODPATH/payload/.brand" "$MODPATH/var/state/brand"
  else
    echo "xiaomi" > "$MODPATH/var/state/brand"
  fi

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

    # ========== 原厂备份（在覆盖前） ==========
    backup_original_bootanim >/dev/null 2>&1
    if [ -f "$ORIGINAL_ZIP" ]; then
      ui_print "- 已备份原厂开机动画"
    else
      ui_print "! 未找到原厂开机动画，无法备份"
    fi

    # ========== 准备 payload ==========
    if prepare_payload; then
      refresh_overlay_tree >/dev/null 2>&1
      record_status "install"
      update_module_prop_description "$(selected_display_name)"
      ui_print "- 品牌：$(get_brand)"
      ui_print "- 已检测到内置动画包：$(payload_size_bytes) bytes"
      library_total=$(payload_library_count)
      ui_print "- 动画库共 $library_total 个动画，可在模块设置中切换"
      ui_print "- 默认动画：$(selected_source_name)"
    else
      ui_print "! 缺少 payload/bootanimation.zip"
    fi
  fi
fi