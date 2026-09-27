#!/system/bin/sh

: "${MODDIR:=${0%/*}}"

# ========== 基础变量 ==========
MODID=hyperosbootanim
DEFAULT_SOURCE_NAME="payload/MIUI粒子效果.zip"
MODULE_BASE_DESCRIPTION="免改分区替换 HyperOS 开机动画"
MODULE_BASE_DESCRIPTION_EN="Replace boot animation without repartition"
MODULE_NAME_ZH="HyperOS 开机动画模块(三改)"
MODULE_NAME_EN="HyperOS Boot Animation Module"
PAYLOAD_DIR="$MODDIR/payload"
PAYLOAD_FILE="$PAYLOAD_DIR/bootanimation.zip"
PAYLOAD_LIBRARY_DIR="$PAYLOAD_DIR/animations"
PAYLOAD_BACKUP_DIR="$PAYLOAD_DIR/backups"
PAYLOAD_BACKUP_INDEX="$PAYLOAD_BACKUP_DIR/index.txt"

LOG_DIR="$MODDIR/var/logs"
STATE_DIR="$MODDIR/var/state"
STATUS_FILE="$STATE_DIR/status.txt"
TMP_DIR="$MODDIR/var/tmp"

OVERLAY_META_FILE="$STATE_DIR/overlay-tree.meta"
SELECTED_SOURCE_FILE="$STATE_DIR/selected_animation.txt"
MODULE_DISABLED_FILE="$STATE_DIR/disabled"
IMPORT_BUSY_FILE="$STATE_DIR/import-busy"
LAST_IMPORT_FILE="$STATE_DIR/last-import.txt"
VALIDATION_LOG_FILE="$STATE_DIR/validation.log"
ACTIVATE_LOG_FILE="$STATE_DIR/activate.log"
LANGUAGE_FILE="$STATE_DIR/language"
THEME_FILE="$STATE_DIR/theme"
BRAND_FILE="$STATE_DIR/brand"

PLAY_MODE_FILE="$STATE_DIR/play_mode"
SEQUENTIAL_INDEX_FILE="$STATE_DIR/sequential_index"

UNDO_DIR="$STATE_DIR/undo"
UNDO_FILE="$UNDO_DIR/last-undo.txt"

NONMODULE_DIR="/data/adb/$MODID"
ORIGINAL_DIR="$NONMODULE_DIR/original"
ORIGINAL_ZIP="$ORIGINAL_DIR/bootanimation.zip"
ORIGINAL_SOURCE="$ORIGINAL_DIR/source.txt"
CONFIG_DIR="$NONMODULE_DIR/configs"

# ========== 工具探测 ==========
TERMUX_PREFIX="/data/data/com.termux/files/usr"

# zip
if [ -x /system/xbin/zip ]; then
  ZIP_BIN="/system/xbin/zip"
elif [ -x /system/bin/zip ]; then
  ZIP_BIN="/system/bin/zip"
elif [ -x "$MODDIR/bin/zip" ]; then
  ZIP_BIN="$MODDIR/bin/zip"
elif [ -x "$TERMUX_PREFIX/bin/zip" ]; then
  ZIP_BIN="$TERMUX_PREFIX/bin/zip"
  export LD_LIBRARY_PATH="$TERMUX_PREFIX/lib:$LD_LIBRARY_PATH"
elif command -v zip >/dev/null 2>&1; then
  ZIP_BIN="zip"
else
  ZIP_BIN=""
fi

# unzip
if [ -x /system/xbin/unzip ]; then
  UNZIP_BIN="/system/xbin/unzip"
elif [ -x /system/bin/unzip ]; then
  UNZIP_BIN="/system/bin/unzip"
elif [ -x /data/adb/ksu/bin/busybox ] && /data/adb/ksu/bin/busybox --list 2>/dev/null | grep -qx unzip; then
  UNZIP_BIN="/data/adb/ksu/bin/busybox unzip"
elif [ -x /data/adb/magisk/busybox ] && /data/adb/magisk/busybox --list 2>/dev/null | grep -qx unzip; then
  UNZIP_BIN="/data/adb/magisk/busybox unzip"
elif [ -x "$TERMUX_PREFIX/bin/unzip" ]; then
  UNZIP_BIN="$TERMUX_PREFIX/bin/unzip"
  export LD_LIBRARY_PATH="$TERMUX_PREFIX/lib:$LD_LIBRARY_PATH"
elif command -v unzip >/dev/null 2>&1; then
  UNZIP_BIN="unzip"
else
  UNZIP_BIN=""
fi

# ffmpeg
if [ -x "$MODDIR/bin/ffmpeg" ]; then
  FFMPEG_BIN="$MODDIR/bin/ffmpeg"
elif [ -x "$TERMUX_PREFIX/bin/ffmpeg" ]; then
  FFMPEG_BIN="$TERMUX_PREFIX/bin/ffmpeg"
  export LD_LIBRARY_PATH="$TERMUX_PREFIX/lib:$LD_LIBRARY_PATH"
elif command -v ffmpeg >/dev/null 2>&1; then
  FFMPEG_BIN="ffmpeg"
else
  FFMPEG_BIN=""
fi

# ========== 运行时目录 ==========
ensure_runtime_dirs() {
  mkdir -p "$PAYLOAD_DIR" "$PAYLOAD_LIBRARY_DIR" "$PAYLOAD_BACKUP_DIR" \
           "$LOG_DIR" "$STATE_DIR" "$TMP_DIR" "$UNDO_DIR" \
           "$ORIGINAL_DIR" "$CONFIG_DIR" 2>/dev/null
}

# ========== 品牌 ==========
get_brand() {
  if [ -f "$BRAND_FILE" ]; then
    cat "$BRAND_FILE" 2>/dev/null
  else
    echo "xiaomi"
  fi
}

is_xiaomi_brand() { [ "$(get_brand)" = "xiaomi" ]; }
is_oneplus_brand() { [ "$(get_brand)" = "oneplus" ]; }

# ========== 日志 ==========
log_msg() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# ========== 语言 ==========
get_language() {
  if [ -f "$LANGUAGE_FILE" ]; then
    cat "$LANGUAGE_FILE" 2>/dev/null
  else
    echo "zh"
  fi
}

set_language() {
  echo "$1" > "$LANGUAGE_FILE"
}

# ========== 主题 ==========
get_theme() {
  if [ -f "$THEME_FILE" ]; then
    cat "$THEME_FILE" 2>/dev/null
  else
    echo "light"
  fi
}

set_theme() {
  echo "$1" > "$THEME_FILE"
}

# ========== 播放模式 ==========
get_play_mode() {
  if [ -f "$PLAY_MODE_FILE" ]; then
    cat "$PLAY_MODE_FILE" 2>/dev/null
  else
    echo "off"
  fi
}

set_play_mode() {
  echo "$1" > "$PLAY_MODE_FILE"
}

get_all_animations_sorted() {
  library_seen_reset
  for entry in "$PAYLOAD_DIR"/*.zip "$PAYLOAD_LIBRARY_DIR"/*.zip; do
    [ -f "$entry" ] || continue
    [ "$entry" = "$PAYLOAD_FILE" ] && continue
    library_entry_excluded "$entry" && continue
    echo "$entry"
  done | sort
}

apply_play_mode() {
  if module_disabled; then
    return 0
  fi

  mode=$(get_play_mode)
  [ "$mode" = "off" ] && return 0

  animations=$(get_all_animations_sorted)
  count=$(echo "$animations" | wc -l)
  [ "$count" -lt 2 ] && return 0

  case "$mode" in
    random)
      current=$(selected_source_name)
      candidates=$(echo "$animations" | grep -vF "$current")
      candidate_count=$(echo "$candidates" | wc -l)
      if [ "$candidate_count" -gt 0 ]; then
        selected=$(echo "$candidates" | shuf -n 1)
      else
        selected=$(echo "$animations" | shuf -n 1)
      fi
      [ -n "$selected" ] && activate_payload_from_path "$selected" "$(payload_library_relative_path "$selected")"
      ;;
    sequential)
      last_index=$(cat "$SEQUENTIAL_INDEX_FILE" 2>/dev/null || echo "0")
      next_index=$(( (last_index) % count + 1 ))
      selected=$(echo "$animations" | sed -n "${next_index}p")
      [ -n "$selected" ] && activate_payload_from_path "$selected" "$(payload_library_relative_path "$selected")"
      echo "$next_index" > "$SEQUENTIAL_INDEX_FILE"
      ;;
  esac

  refresh_overlay_tree
  deploy_bind_mounts
}

# ========== payload 基础 ==========
payload_size_bytes() {
  if [ -f "$PAYLOAD_FILE" ]; then
    wc -c <"$PAYLOAD_FILE" 2>/dev/null
  else
    echo 0
  fi
}

has_payload() {
  [ -s "$PAYLOAD_FILE" ]
}

# ========== 校验 ==========
is_bootanimation_archive() {
  ensure_runtime_dirs
  archive_path="$1"
  detail_tmp="$TMP_DIR/.validation.$$.log"
  : >"$detail_tmp"

  echo "path=$archive_path" >>"$detail_tmp"
  if [ -f "$archive_path" ]; then
    echo "size=$(wc -c <"$archive_path" 2>/dev/null)" >>"$detail_tmp"
  else
    echo "size=missing" >>"$detail_tmp"
  fi

  if [ ! -s "$archive_path" ]; then
    echo "status=REJECT empty or missing file" >>"$detail_tmp"
    mv -f "$detail_tmp" "$VALIDATION_LOG_FILE" 2>/dev/null
    return 1
  fi

  magic=$(dd if="$archive_path" bs=2 count=1 2>/dev/null)
  echo "magic=[$magic]" >>"$detail_tmp"
  if [ "$magic" != "PK" ]; then
    echo "status=REJECT bad zip magic" >>"$detail_tmp"
    mv -f "$detail_tmp" "$VALIDATION_LOG_FILE" 2>/dev/null
    return 1
  fi

  if command -v unzip >/dev/null 2>&1; then
    echo "unzip=$(command -v unzip)" >>"$detail_tmp"
    list_tmp="$TMP_DIR/.ziplist.$$.txt"
    err_tmp="$TMP_DIR/.ziplist.$$.err"
    unzip -l "$archive_path" >"$list_tmp" 2>"$err_tmp"
    list_status=$?
    if [ "$list_status" -eq 0 ]; then
      echo "unzip_l=ok" >>"$detail_tmp"
      if grep -q 'desc\.txt' "$list_tmp"; then
        echo "desc.txt=found" >>"$detail_tmp"
        rm -f "$list_tmp" "$err_tmp" "$detail_tmp"
        return 0
      else
        echo "desc.txt=missing" >>"$detail_tmp"
        echo "status=REJECT root desc.txt not found" >>"$detail_tmp"
        mv -f "$detail_tmp" "$VALIDATION_LOG_FILE" 2>/dev/null
        rm -f "$list_tmp" "$err_tmp"
        return 1
      fi
    else
      echo "unzip_l=failed exit=$list_status" >>"$detail_tmp"
      echo "unzip_l_err=$(tr '\n' ' ' <"$err_tmp" 2>/dev/null | head -c 300)" >>"$detail_tmp"
      rm -f "$list_tmp" "$err_tmp" "$detail_tmp"
      return 0
    fi
  fi

  rm -f "$detail_tmp"
  return 0
}

# ========== 动画库扫描 ==========
library_entry_excluded() {
  candidate_path="$1"
  case "$candidate_path" in
    *hyperosbootanim-*.zip)
      return 0
      ;;
  esac
  return 1
}

library_seen_reset() {
  library_seen=""
}

library_seen_has() {
  seen_name="$1"
  case "$library_seen" in
    *"|$seen_name|"*)
      return 0
      ;;
  esac
  return 1
}

library_seen_add() {
  seen_name="$1"
  library_seen="${library_seen}|${seen_name}|"
}

unique_library_target() {
  requested_name="$1"
  base_name=${requested_name%.zip}
  candidate_name="$requested_name"
  candidate_index=2
  while [ -e "$PAYLOAD_DIR/$candidate_name" ] || [ -e "$PAYLOAD_LIBRARY_DIR/$candidate_name" ]; do
    candidate_name="${base_name}-${candidate_index}.zip"
    candidate_index=$((candidate_index + 1))
  done
  printf '%s\n' "$candidate_name"
}

payload_library_entries() {
  library_seen_reset
  for library_candidate in "$PAYLOAD_DIR"/*.zip "$PAYLOAD_LIBRARY_DIR"/*.zip; do
    [ -f "$library_candidate" ] || continue
    [ "$library_candidate" = "$PAYLOAD_FILE" ] && continue
    library_entry_excluded "$library_candidate" && continue
    library_candidate_name=$(basename "$library_candidate")
    if library_seen_has "$library_candidate_name"; then
      continue
    fi
    library_seen_add "$library_candidate_name"
    printf '%s\n' "$library_candidate"
  done
}

payload_library_count() {
  library_count=0
  library_seen_reset
  for library_candidate in "$PAYLOAD_DIR"/*.zip "$PAYLOAD_LIBRARY_DIR"/*.zip; do
    [ -f "$library_candidate" ] || continue
    [ "$library_candidate" = "$PAYLOAD_FILE" ] && continue
    library_entry_excluded "$library_candidate" && continue
    library_candidate_name=$(basename "$library_candidate")
    if library_seen_has "$library_candidate_name"; then
      continue
    fi
    library_seen_add "$library_candidate_name"
    library_count=$((library_count + 1))
  done
  echo "$library_count"
}

payload_library_entry_at() {
  requested_index="$1"
  current_index=0
  library_seen_reset

  for library_candidate in "$PAYLOAD_DIR"/*.zip "$PAYLOAD_LIBRARY_DIR"/*.zip; do
    [ -f "$library_candidate" ] || continue
    [ "$library_candidate" = "$PAYLOAD_FILE" ] && continue
    library_entry_excluded "$library_candidate" && continue
    library_candidate_name=$(basename "$library_candidate")
    if library_seen_has "$library_candidate_name"; then
      continue
    fi
    library_seen_add "$library_candidate_name"
    current_index=$((current_index + 1))
    if [ "$current_index" = "$requested_index" ]; then
      printf '%s\n' "$library_candidate"
      return 0
    fi
  done

  return 1
}

payload_library_relative_path() {
  library_path="$1"
  case "$library_path" in
    "$MODDIR"/*)
      printf '%s\n' "${library_path#"$MODDIR"/}"
      ;;
    *)
      return 1
      ;;
  esac
}

# ========== 选中来源 ==========
selected_source_name() {
  if [ -s "$SELECTED_SOURCE_FILE" ]; then
    cat "$SELECTED_SOURCE_FILE" 2>/dev/null
  else
    echo "payload/bootanimation.zip"
  fi
}

selected_display_name() {
  display_value=$(selected_source_name)
  case "$display_value" in
    payload/animations/*)
      display_value=${display_value#payload/animations/}
      ;;
    payload/*)
      display_value=${display_value#payload/}
      ;;
  esac
  display_value=${display_value%.zip}
  printf '%s\n' "$display_value"
}

set_selected_source_name() {
  selected_source_name_value="$1"
  selected_source_tmp="$TMP_DIR/.selected_animation.$$.tmp"
  printf '%s\n' "$selected_source_name_value" >"$selected_source_tmp" || return 1
  mv -f "$selected_source_tmp" "$SELECTED_SOURCE_FILE" || return 1
}

# ========== module.prop 描述更新 ==========
update_module_prop_description() {
  prop_value="$1"
  [ -f "$MODDIR/module.prop" ] || return 0
  ensure_runtime_dirs
  prop_tmp="$TMP_DIR/.module.prop.$$.tmp"
  lang=$(get_language)
  if [ "$lang" = "en" ]; then
    new_desc="Active: $prop_value. $MODULE_BASE_DESCRIPTION_EN"
  else
    new_desc="当前生效动画：$prop_value。$MODULE_BASE_DESCRIPTION"
  fi
  awk -v nd="$new_desc" 'BEGIN { FS = OFS = "=" } $1 == "description" { print "description=" nd; next } { print }' "$MODDIR/module.prop" >"$prop_tmp" 2>/dev/null || return 1
  mv -f "$prop_tmp" "$MODDIR/module.prop" 2>/dev/null || return 1
  return 0
}

# ========== 启用/禁用 ==========
module_disabled() {
  [ -f "$MODULE_DISABLED_FILE" ]
}

set_module_disabled() {
  ensure_runtime_dirs
  : >"$MODULE_DISABLED_FILE" 2>/dev/null || return 1
  log_msg "module animation disabled"
  return 0
}

clear_module_disabled() {
  rm -f "$MODULE_DISABLED_FILE"
}

# ========== 导入忙标记 ==========
import_busy_active() {
  [ -f "$IMPORT_BUSY_FILE" ]
}

set_import_busy() {
  ensure_runtime_dirs
  : >"$IMPORT_BUSY_FILE" 2>/dev/null || return 1
  return 0
}

clear_import_busy() {
  rm -f "$IMPORT_BUSY_FILE"
}

# ========== 激活 payload ==========
activate_payload_from_path() {
  source_path="$1"
  source_label="$2"
  active_payload_tmp="$TMP_DIR/.bootanimation.zip.$$.tmp"
  activate_log_tmp="$TMP_DIR/.activate.$$.log"
  : >"$activate_log_tmp"

  echo "source_path=$source_path" >>"$activate_log_tmp"
  echo "source_label=$source_label" >>"$activate_log_tmp"

  if ! is_bootanimation_archive "$source_path"; then
    echo "step=validation FAILED" >>"$activate_log_tmp"
    mv -f "$activate_log_tmp" "$ACTIVATE_LOG_FILE" 2>/dev/null
    log_msg "archive validation failed: $source_path"
    return 1
  fi
  echo "step=validation ok" >>"$activate_log_tmp"

  if [ "$source_label" = "$(selected_source_name)" ] && [ -f "$PAYLOAD_FILE" ]; then
    rm -f "$activate_log_tmp" 2>/dev/null
    update_module_prop_description "$(selected_display_name)"
    return 0
  fi

  rm -f "$active_payload_tmp" 2>/dev/null
  if ! cp -fp "$source_path" "$active_payload_tmp" 2>/dev/null; then
    echo "step=copy failed" >>"$activate_log_tmp"
    mv -f "$activate_log_tmp" "$ACTIVATE_LOG_FILE" 2>/dev/null
    return 1
  fi
  echo "step=independent copy ok" >>"$activate_log_tmp"
  chmod 0644 "$active_payload_tmp" 2>/dev/null

  rm -f "$PAYLOAD_FILE" 2>/dev/null
  if mv -f "$active_payload_tmp" "$PAYLOAD_FILE" 2>/dev/null; then
    echo "step=mv ok" >>"$activate_log_tmp"
  else
    echo "step=mv failed, recreate safely" >>"$activate_log_tmp"
    if ! cp -fp "$active_payload_tmp" "$PAYLOAD_FILE" 2>/dev/null; then
      echo "step=recreate failed" >>"$activate_log_tmp"
      mv -f "$activate_log_tmp" "$ACTIVATE_LOG_FILE" 2>/dev/null
      return 1
    fi
    rm -f "$active_payload_tmp" 2>/dev/null
    echo "step=recreate ok" >>"$activate_log_tmp"
  fi

  if set_selected_source_name "$source_label"; then
    echo "step=save label ok" >>"$activate_log_tmp"
  else
    echo "step=save label tmp failed, direct write" >>"$activate_log_tmp"
    if ! printf '%s\n' "$source_label" >"$SELECTED_SOURCE_FILE" 2>/dev/null; then
      echo "step=save label direct failed" >>"$activate_log_tmp"
      mv -f "$activate_log_tmp" "$ACTIVATE_LOG_FILE" 2>/dev/null
      return 1
    fi
  fi

  rm -f "$activate_log_tmp" 2>/dev/null
  update_module_prop_description "$(selected_display_name)"
  return 0
}

bootstrap_payload_from_library() {
  saved_source=$(selected_source_name)
  case "$saved_source" in
    payload/*)
      saved_source_path="$MODDIR/$saved_source"
      if [ -f "$saved_source_path" ]; then
        activate_payload_from_path "$saved_source_path" "$saved_source" && return 0
      fi
      ;;
  esac

  default_source_path="$MODDIR/$DEFAULT_SOURCE_NAME"
  if [ -f "$default_source_path" ]; then
    activate_payload_from_path "$default_source_path" "$DEFAULT_SOURCE_NAME" && return 0
  fi

  for bootstrap_candidate in "$PAYLOAD_DIR"/*.zip "$PAYLOAD_LIBRARY_DIR"/*.zip; do
    [ -f "$bootstrap_candidate" ] || continue
    [ "$bootstrap_candidate" = "$PAYLOAD_FILE" ] && continue
    library_entry_excluded "$bootstrap_candidate" && continue
    bootstrap_label=$(payload_library_relative_path "$bootstrap_candidate") || continue
    activate_payload_from_path "$bootstrap_candidate" "$bootstrap_label" && return 0
  done

  return 1
}

# ========== payload 指纹 ==========
payload_fingerprint() {
  if has_payload; then
    if command -v md5sum >/dev/null 2>&1; then
      echo "md5=$(md5sum "$PAYLOAD_FILE" 2>/dev/null | awk '{print $1}') size=$(payload_size_bytes)"
    else
      echo "size=$(payload_size_bytes)"
    fi
  else
    echo "size=0"
  fi
}

# ========== 外部导入源 ==========
payload_sources() {
  cat <<'EOF'
/data/adb/hyperosbootanim/bootanimation.zip
/data/local/tmp/CustomBoot/bootanimation.zip
/data/local/tmp/bootanimation.zip
/data/media/0/CustomBoot/bootanimation.zip
/storage/emulated/0/CustomBoot/bootanimation.zip
/sdcard/CustomBoot/bootanimation.zip
EOF
}

import_payload_from_sources() {
  ensure_runtime_dirs

  for source_path in $(payload_sources); do
    [ -n "$source_path" ] || continue
    if [ -f "$source_path" ]; then
      imported_file="$PAYLOAD_LIBRARY_DIR/imported-external.zip"
      imported_tmp="$TMP_DIR/.imported-external.$$.tmp"
      cp -fp "$source_path" "$imported_tmp" 2>/dev/null || return 1
      if ! is_bootanimation_archive "$imported_tmp"; then
        rm -f "$imported_tmp"
        log_msg "ignored invalid external archive: $source_path"
        return 1
      fi
      mv -f "$imported_tmp" "$imported_file" || return 1
      chmod 0644 "$imported_file" 2>/dev/null
      activate_payload_from_path "$imported_file" "payload/animations/imported-external.zip" || return 1
      echo "$source_path" >"$STATE_DIR/last_import_source.txt"
      log_msg "imported payload from $source_path"
      return 0
    fi
  done

  return 1
}

prepare_payload() {
  if module_disabled; then
    log_msg "module disabled, payload intentionally inactive"
    return 1
  fi

  if has_payload; then
    return 0
  fi

  if bootstrap_payload_from_library; then
    return 0
  fi

  if import_payload_from_sources; then
    return 0
  fi

  log_msg "payload missing"
  return 1
}

# ========== 原厂备份 ==========
backup_original_bootanim() {
  ensure_runtime_dirs

  if [ -f "$ORIGINAL_ZIP" ]; then
    return 0
  fi

  for target_path in $(device_target_paths); do
    [ -n "$target_path" ] || continue
    if [ -f "$target_path" ]; then
      cp -fp "$target_path" "$ORIGINAL_ZIP" 2>/dev/null || continue
      chmod 0644 "$ORIGINAL_ZIP" 2>/dev/null
      printf '%s\n' "$target_path" >"$ORIGINAL_SOURCE"
      log_msg "original bootanimation backed up from $target_path"
      return 0
    fi
  done

  log_msg "no original bootanimation found"
  return 1
}

# ========== 路径：MIUI / HyperOS ==========
product_prop_relpath() {
  prop_path=$(getprop ro.product.bootanim.file 2>/dev/null)
  case "$prop_path" in
    "")
      ;;
    /*)
      ;;
    *)
      echo "$prop_path"
      ;;
  esac
}

product_prop_abspath() {
  prop_path=$(getprop ro.product.bootanim.file 2>/dev/null)
  case "$prop_path" in
    "")
      ;;
    /product/*|/system/product/*|/system/*|/system_ext/*)
      echo "$prop_path"
      ;;
    *)
      echo "/product/media/$prop_path"
      ;;
  esac
}

product_prop_module_path() {
  prop_path=$(product_prop_abspath)
  case "$prop_path" in
    "")
      ;;
    /product/*)
      echo "system$prop_path"
      ;;
    /system/product/*)
      echo "${prop_path#/}"
      ;;
    /system/*)
      echo "${prop_path#/}"
      ;;
    /system_ext/*)
      echo "system/system_ext${prop_path#/system_ext}"
      ;;
  esac
}

xiaomi_module_target_paths() {
  {
    cat <<'EOF'
system/product/media/bootanimation.zip
system/product/media/bootanimation-dark.zip
system/media/bootanimation.zip
system/media/theme/bootanimation.zip
system/media/theme/cust_config/global/bootanimation.zip
system/media/theme/cust_config/cn/bootanimation.zip
system/media/theme/cust_config/india/bootanimation.zip
system/system_ext/media/bootanimation.zip
EOF
    product_prop_module_path
  } | awk 'NF && !seen[$0]++'
}

xiaomi_device_target_paths() {
  {
    cat <<'EOF'
/apex/com.android.bootanimation/etc/bootanimation.zip
/product/media/bootanimation.zip
/product/media/bootanimation-dark.zip
/oem/media/bootanimation.zip
/system/media/bootanimation.zip
/system/media/theme/bootanimation.zip
/system/media/theme/cust_config/global/bootanimation.zip
/system/media/theme/cust_config/cn/bootanimation.zip
/system/media/theme/cust_config/india/bootanimation.zip
/system_ext/media/bootanimation.zip
/system/product/media/bootanimation.zip
/system/product/media/bootanimation-dark.zip
/system/system_ext/media/bootanimation.zip
EOF
    product_prop_abspath
  } | awk 'NF && !seen[$0]++'
}

# ========== 路径：一加 ==========
oneplus_bootanim_paths() {
  cat <<'EOF'
/system/media/bootanimation.zip
/system/product/media/bootanimation.zip
/my_product/media/bootanimation/bootanimation.zip
/op1/bootanimation/bootanimation.zip
/system_ext/media/bootanimation.zip
/vendor/media/bootanimation.zip
EOF
}

scan_oneplus_targets() {
  oneplus_bootanim_paths | while read -r path; do
    [ -n "$path" ] || continue
    if [ -f "$path" ]; then
      echo "$path"
    fi
  done
}

oneplus_module_target_paths() {
  scan_oneplus_targets | while read -r target_path; do
    echo "${target_path#/}"
  done
}

# ========== 路径：通用分发 ==========
module_target_paths() {
  if is_oneplus_brand; then
    oneplus_module_target_paths
  else
    xiaomi_module_target_paths
  fi
}

device_target_paths() {
  if is_oneplus_brand; then
    scan_oneplus_targets
  else
    xiaomi_device_target_paths
  fi
}

# ========== overlay tree ==========
overlay_tree_has_all_targets() {
  for rel_path in $(module_target_paths); do
    [ -n "$rel_path" ] || continue
    [ -f "$MODDIR/$rel_path" ] || return 1
  done
  return 0
}

overlay_tree_current() {
  has_payload || return 1
  [ -f "$OVERLAY_META_FILE" ] || return 1
  overlay_tree_has_all_targets || return 1

  current_meta=$(cat "$OVERLAY_META_FILE" 2>/dev/null)
  expected_meta=$(payload_fingerprint)
  [ "$current_meta" = "$expected_meta" ]
}

overlay_payload_relative_path() {
  overlay_rel_dir=${1%/*}
  overlay_ups=""
  while [ "$overlay_rel_dir" != "${overlay_rel_dir%/*}" ]; do
    overlay_rel_dir=${overlay_rel_dir%/*}
    overlay_ups="../$overlay_ups"
  done
  printf '%s\n' "${overlay_ups}payload/bootanimation.zip"
}

refresh_overlay_tree_xiaomi() {
  prepare_payload || return 1
  ensure_runtime_dirs || return 1

  stage_root="$TMP_DIR/.overlay-tree.$$.new"
  backup_root="$TMP_DIR/.overlay-tree.$$.old"
  stage_tree="$stage_root/system"
  rm -rf "$stage_root" "$backup_root" 2>/dev/null
  mkdir -p "$stage_tree" 2>/dev/null || {
    rm -rf "$stage_root" "$backup_root" 2>/dev/null
    return 1
  }

  for rel_path in $(xiaomi_module_target_paths); do
    [ -n "$rel_path" ] || continue
    dst="$stage_root/${rel_path}"
    mkdir -p "${dst%/*}" 2>/dev/null || {
      rm -rf "$stage_root" "$backup_root" 2>/dev/null
      return 1
    }
    if ! ln -f "$PAYLOAD_FILE" "$dst" 2>/dev/null; then
      link_target=$(overlay_payload_relative_path "$rel_path")
      if ! ln -s "$link_target" "$dst" 2>/dev/null; then
        cp -fp "$PAYLOAD_FILE" "$dst" 2>/dev/null || {
          rm -rf "$stage_root" "$backup_root" 2>/dev/null
          return 1
        }
      fi
    fi
    chmod 0644 "$dst" 2>/dev/null || :
  done

  expected_meta=$(payload_fingerprint)
  [ -n "$expected_meta" ] || {
    rm -rf "$stage_root" "$backup_root" 2>/dev/null
    return 1
  }

  had_previous_system=0
  if [ -e "$MODDIR/system" ] || [ -L "$MODDIR/system" ]; then
    had_previous_system=1
    mv -f "$MODDIR/system" "$backup_root" 2>/dev/null || {
      rm -rf "$stage_root" "$backup_root" 2>/dev/null
      return 1
    }
  fi

  if ! mv -f "$stage_tree" "$MODDIR/system" 2>/dev/null; then
    if [ "$had_previous_system" -eq 1 ]; then
      mv -f "$backup_root" "$MODDIR/system" 2>/dev/null
    fi
    rm -rf "$stage_root" "$backup_root" 2>/dev/null
    return 1
  fi

  if ! printf '%s\n' "$expected_meta" >"$OVERLAY_META_FILE" 2>/dev/null; then
    rm -rf "$MODDIR/system" 2>/dev/null
    if [ "$had_previous_system" -eq 1 ]; then
      mv -f "$backup_root" "$MODDIR/system" 2>/dev/null
    fi
    rm -rf "$stage_root" "$backup_root" 2>/dev/null
    return 1
  fi

  rm -rf "$stage_root" "$backup_root" 2>/dev/null || :

  log_msg "overlay tree refreshed (xiaomi)"
  return 0
}

refresh_overlay_tree_oneplus() {
  prepare_payload || return 1
  ensure_runtime_dirs || return 1

  roots=""
  for rel_path in $(oneplus_module_target_paths); do
    root=${rel_path%%/*}
    [ -n "$root" ] || continue
    case " $roots " in
      *" $root "*) ;;
      *) roots="$roots $root" ;;
    esac
  done

  [ -n "$roots" ] || return 1

  expected_meta=$(payload_fingerprint)
  [ -n "$expected_meta" ] || return 1

  for root in $roots; do
    [ -n "$root" ] || continue

    stage_root="$TMP_DIR/.overlay-$root.$$.new"
    backup_root="$TMP_DIR/.overlay-$root.$$.old"
    stage_tree="$stage_root/$root"
    rm -rf "$stage_root" "$backup_root" 2>/dev/null
    mkdir -p "$stage_tree" 2>/dev/null || {
      rm -rf "$stage_root" "$backup_root" 2>/dev/null
      return 1
    }

    for rel_path in $(oneplus_module_target_paths); do
      case "$rel_path" in
        "$root"/*) ;;
        *) continue ;;
      esac
      dst="$stage_root/${rel_path}"
      mkdir -p "${dst%/*}" 2>/dev/null || {
        rm -rf "$stage_root" "$backup_root" 2>/dev/null
        return 1
      }
      if ! ln -f "$PAYLOAD_FILE" "$dst" 2>/dev/null; then
        link_target=$(overlay_payload_relative_path "$rel_path")
        if ! ln -s "$link_target" "$dst" 2>/dev/null; then
          cp -fp "$PAYLOAD_FILE" "$dst" 2>/dev/null || {
            rm -rf "$stage_root" "$backup_root" 2>/dev/null
            return 1
          }
        fi
      fi
      chmod 0644 "$dst" 2>/dev/null || :
    done

    had_previous=0
    if [ -e "$MODDIR/$root" ] || [ -L "$MODDIR/$root" ]; then
      had_previous=1
      mv -f "$MODDIR/$root" "$backup_root" 2>/dev/null || {
        rm -rf "$stage_root" "$backup_root" 2>/dev/null
        return 1
      }
    fi

    if ! mv -f "$stage_tree" "$MODDIR/$root" 2>/dev/null; then
      if [ "$had_previous" -eq 1 ]; then
        mv -f "$backup_root" "$MODDIR/$root" 2>/dev/null
      fi
      rm -rf "$stage_root" "$backup_root" 2>/dev/null
      return 1
    fi

    rm -rf "$stage_root" "$backup_root" 2>/dev/null || :
  done

  printf '%s\n' "$expected_meta" >"$OVERLAY_META_FILE"

  log_msg "overlay tree refreshed (oneplus)"
  return 0
}

refresh_overlay_tree() {
  if is_oneplus_brand; then
    refresh_overlay_tree_oneplus
  else
    refresh_overlay_tree_xiaomi
  fi
}

ensure_overlay_tree() {
  if overlay_tree_current; then
    return 0
  fi
  refresh_overlay_tree
}

# ========== bind mount ==========
target_exists_or_wait() {
  target_path="$1"

  if [ -e "$target_path" ]; then
    return 0
  fi

  case "$target_path" in
    /apex/com.android.bootanimation/*)
      retry=0
      while [ "$retry" -lt 5 ]; do
        sleep 0.1
        [ -e "$target_path" ] && return 0
        retry=$((retry + 1))
      done
      ;;
    *)
      ;;
  esac

  return 1
}

is_mounted_on_target() {
  target_path="$1"
  grep -F " $target_path " /proc/self/mountinfo >/dev/null 2>&1
}

bind_mount_target() {
  target_path="$1"

  if ! target_exists_or_wait "$target_path"; then
    return 1
  fi

  if is_mounted_on_target "$target_path"; then
    return 0
  fi

  if mount -o bind "$PAYLOAD_FILE" "$target_path" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

deploy_bind_mounts() {
  prepare_payload || return 1

  for target_path in $(device_target_paths); do
    [ -n "$target_path" ] || continue
    if bind_mount_target "$target_path"; then
      log_msg "bind ok: $target_path"
    else
      log_msg "bind fail/skip: $target_path"
    fi
  done
}

# ========== 状态记录 ==========
record_status() {
  ensure_runtime_dirs
  stage_name="$1"
  prop_path=$(getprop ro.product.bootanim.file 2>/dev/null)

  {
    echo "stage=$stage_name"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "android_release=$(getprop ro.build.version.release 2>/dev/null)"
    echo "sdk=$(getprop ro.build.version.sdk 2>/dev/null)"
    echo "brand=$(get_brand)"
    echo "theme=$(get_theme)"
    echo "language=$(get_language)"
    echo "play_mode=$(get_play_mode)"
    if is_xiaomi_brand; then
      echo "hyperos_version=$(getprop ro.mi.os.version.name 2>/dev/null)"
      echo "hyperos_incremental=$(getprop ro.system.build.version.incremental 2>/dev/null)"
      echo "product_bootanim_property=$prop_path"
    fi
    echo "payload_present=$([ -f "$PAYLOAD_FILE" ] && echo yes || echo no)"
    echo "payload_size=$(payload_size_bytes)"
    echo "selected_source=$(selected_source_name)"
    echo "module_disabled=$(module_disabled && echo yes || echo no)"
    echo "import_busy=$(import_busy_active && echo yes || echo no)"
    echo "last_import=$(cat "$LAST_IMPORT_FILE" 2>/dev/null)"
    echo "available_animations=$(payload_library_count)"
    if overlay_tree_current; then
      echo "overlay_tree_current=yes"
    else
      echo "overlay_tree_current=no"
    fi
    echo "overlay_tree_meta=$(cat "$OVERLAY_META_FILE" 2>/dev/null)"
    echo "bind_mounts:"
    grep -E '/bootanimation\.zip' /proc/self/mountinfo 2>/dev/null | sed 's/^/  /'
    echo "candidate_targets:"
    device_target_paths | sed 's/^/  - /'
  } >"$STATUS_FILE"
}

# ========== desc.txt 解析 ==========


parse_desc_geometry() {
  desc_file="$1"
  [ -f "$desc_file" ] || return 1

  format=$(detect_desc_format "$desc_file")
  case "$format" in
    oneplus) parse_desc_oneplus "$desc_file" ;;
    standard) parse_desc_standard "$desc_file" ;;
    *) return 1 ;;
  esac
}

detect_desc_format() {
  desc_file="$1"
  [ -f "$desc_file" ] || { echo "unknown"; return 1; }

  if grep -qE '^[[:space:]]*g[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+' "$desc_file" 2>/dev/null; then
    echo "oneplus"
    return 0
  fi

  if grep -qE '^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+' "$desc_file" 2>/dev/null; then
    echo "standard"
    return 0
  fi

  echo "unknown"
  return 1
}

read_desc_geometry_from_zip() {
  zip_path="$1"
  [ -f "$zip_path" ] || return 1
  command -v unzip >/dev/null 2>&1 || return 1

  desc_tmp="$TMP_DIR/.desc-read.$$.txt"
  unzip -p "$zip_path" desc.txt >"$desc_tmp" 2>/dev/null || {
    rm -f "$desc_tmp"
    return 1
  }

  format=$(detect_desc_format "$desc_tmp")
  case "$format" in
    standard)
      geometry=$(parse_desc_standard "$desc_tmp")
      rm -f "$desc_tmp"
      [ -n "$geometry" ] || return 1
      printf '%s standard\n' "$geometry"
      return 0
      ;;
    oneplus)
      geometry=$(parse_desc_oneplus "$desc_tmp")
      rm -f "$desc_tmp"
      [ -n "$geometry" ] || return 1
      printf '%s oneplus\n' "$geometry"
      return 0
      ;;
    *)
      rm -f "$desc_tmp"
      return 1
      ;;
  esac
}

read_original_geometry() {
  [ -f "$ORIGINAL_ZIP" ] || return 1
  read_desc_geometry_from_zip "$ORIGINAL_ZIP"
}


# ========== desc 备份 ==========
desc_bak_name() {
  zip_path="$1"
  rel_path=$(payload_library_relative_path "$zip_path") || return 1
  escaped=$(printf '%s' "$rel_path" | sed 's|/|__|g')
  printf '%s\n' "${escaped}.desc.bak"
}

backup_desc_to_bak() {
  zip_path="$1"
  [ -f "$zip_path" ] || return 1
  command -v unzip >/dev/null 2>&1 || return 1

  ensure_runtime_dirs

  bak_name=$(desc_bak_name "$zip_path") || return 1
  bak_path="$PAYLOAD_BACKUP_DIR/$bak_name"

  if [ -f "$bak_path" ]; then
    return 0
  fi

  unzip -p "$zip_path" desc.txt >"$bak_path" 2>/dev/null || {
    rm -f "$bak_path"
    return 1
  }

  rel_path=$(payload_library_relative_path "$zip_path") || return 1
  printf '%s\t%s\n' "$bak_name" "$rel_path" >>"$PAYLOAD_BACKUP_INDEX"

  return 0
}

restore_desc_from_bak() {
  zip_path="$1"
  [ -f "$zip_path" ] || return 1
  command -v zip >/dev/null 2>&1 || return 1

  bak_name=$(desc_bak_name "$zip_path") || return 1
  bak_path="$PAYLOAD_BACKUP_DIR/$bak_name"

  [ -f "$bak_path" ] || return 1

  work_dir="$TMP_DIR/.desc-restore.$$"
  rm -rf "$work_dir"
  mkdir -p "$work_dir" || return 1

  cp -f "$bak_path" "$work_dir/desc.txt" || {
    rm -rf "$work_dir"
    return 1
  }

  ( cd "$work_dir" && zip -q "$zip_path" desc.txt ) 2>/dev/null || {
    rm -rf "$work_dir"
    return 1
  }

  rm -rf "$work_dir"
  return 0
}

list_modified_animations() {
  ensure_runtime_dirs
  [ -f "$PAYLOAD_BACKUP_INDEX" ] || return 0

  while IFS='	' read -r bak_name rel_path; do
    [ -n "$bak_name" ] || continue
    [ -n "$rel_path" ] || continue
    zip_path="$MODDIR/$rel_path"
    [ -f "$zip_path" ] || continue
    [ -f "$PAYLOAD_BACKUP_DIR/$bak_name" ] || continue
    geometry=$(read_desc_geometry_from_zip "$zip_path" 2>/dev/null)
    printf '%s\t%s\t%s\n' "$rel_path" "$bak_name" "$geometry"
  done <"$PAYLOAD_BACKUP_INDEX"
}

# ========== 撤销 ==========
record_undo() {
  ensure_runtime_dirs
  action="$1"
  shift
  {
    echo "action=$action"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    for line in "$@"; do
      echo "path=$line"
    done
  } >"$UNDO_FILE"
}

has_undo() {
  [ -f "$UNDO_FILE" ]
}

read_undo_paths() {
  [ -f "$UNDO_FILE" ] || return 1
  grep '^path=' "$UNDO_FILE" | sed 's/^path=//'
}

clear_undo() {
  rm -f "$UNDO_FILE"
}

apply_undo() {
  has_undo || return 1
  paths=$(read_undo_paths)
  [ -n "$paths" ] || return 1

  for rel_path in $paths; do
    zip_path="$MODDIR/$rel_path"
    [ -f "$zip_path" ] || continue
    restore_desc_from_bak "$zip_path" || continue
  done

  clear_undo
  return 0
}

# ========== 配置 ==========
safe_config_name() {
  name="$1"
  [ -n "$name" ] || return 1
  case "$name" in
    *[!a-zA-Z0-9_一-龥-]*)
      return 1
      ;;
  esac
  bytes=$(printf '%s' "$name" | wc -c | tr -d ' ')
  [ "$bytes" -le 60 ] || return 1
  printf '%s\n' "$name"
}

config_path() {
  name="$1"
  printf '%s/%s.conf\n' "$CONFIG_DIR" "$name"
}

config_exists() {
  name="$1"
  [ -f "$(config_path "$name")" ]
}

#   config_save NAME standard W H FPS
#   config_save NAME oneplus W H OX OY FPS
config_save() {
  name="$1"
  format="$2"
  shift 2

  ensure_runtime_dirs
  safe_config_name "$name" >/dev/null || return 1
  config_exists "$name" && return 2

  case "$format" in
    standard)
      [ $# -ge 3 ] || return 1
      width="$1"; height="$2"; fps="$3"
      offsetx=""
      offsety=""
      ;;
    oneplus)
      [ $# -ge 5 ] || return 1
      width="$1"; height="$2"; offsetx="$3"; offsety="$4"; fps="$5"
      ;;
    *)
      return 1
      ;;
  esac

  cfg="$(config_path "$name")"
  {
    echo "name=$name"
    echo "format=$format"
    echo "width=$width"
    echo "height=$height"
    if [ "$format" = "oneplus" ]; then
      echo "offsetx=$offsetx"
      echo "offsety=$offsety"
    fi
    echo "fps=$fps"
    echo "created=$(date '+%Y-%m-%d %H:%M:%S')"
  } >"$cfg"
  return 0
}

config_delete() {
  name="$1"
  cfg="$(config_path "$name")"
  [ -f "$cfg" ] || return 1
  rm -f "$cfg"
  return 0
}

config_list() {
  ensure_runtime_dirs
  for cfg in "$CONFIG_DIR"/*.conf; do
    [ -f "$cfg" ] || continue
    name=$(grep '^name=' "$cfg" | head -n1 | sed 's/^name=//')
    format=$(grep '^format=' "$cfg" | head -n1 | sed 's/^format=//')
    width=$(grep '^width=' "$cfg" | head -n1 | sed 's/^width=//')
    height=$(grep '^height=' "$cfg" | head -n1 | sed 's/^height=//')
    fps=$(grep '^fps=' "$cfg" | head -n1 | sed 's/^fps=//')
    created=$(grep '^created=' "$cfg" | head -n1 | sed 's/^created=//')

    if [ "$format" = "oneplus" ]; then
      offsetx=$(grep '^offsetx=' "$cfg" | head -n1 | sed 's/^offsetx=//')
      offsety=$(grep '^offsety=' "$cfg" | head -n1 | sed 's/^offsety=//')
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$format" "$width" "$height" "$offsetx" "$offsety" "$fps" "$created"
    else
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$format" "$width" "$height" "$fps" "$created"
    fi
  done
}

# ========== desc.txt 解析（修正版） ==========
parse_desc_standard() {
  desc_file="$1"
  [ -f "$desc_file" ] || return 1

  std_line=$(grep -vE '^[[:space:]]*(#|$|[a-zA-Z])' "$desc_file" 2>/dev/null | head -n1 | tr -d '\r')
  [ -n "$std_line" ] || return 1

  result=$(echo "$std_line" | awk 'NF >= 3 {print $1, $2, $3}' | tr -d '\r')
  [ -n "$result" ] || return 1
  printf '%s\n' "$result"
  return 0
}

parse_desc_oneplus() {
  desc_file="$1"
  [ -f "$desc_file" ] || return 1

  g_line=$(grep -E '^[[:space:]]*g[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+' "$desc_file" 2>/dev/null | head -n1 | tr -d '\r')
  [ -n "$g_line" ] || return 1

  result=$(echo "$g_line" | awk '{print $2, $3, $4, $5, $6}' | tr -d '\r')
  [ -n "$result" ] || return 1
  printf '%s\n' "$result"
  return 0
}

# 用法：
#   write_desc_geometry_to_zip ZIP standard W H FPS
#   write_desc_geometry_to_zip ZIP oneplus W H OX OY FPS
write_desc_geometry_to_zip() {
  [ -n "$ZIP_BIN" ] || { echo "ERROR 设备缺少 zip 命令（改分辨率不可用）"; return 1; }
  zip_path="$1"
  target_format="$2"
  shift 2

  [ -f "$zip_path" ] || return 1
  command -v unzip >/dev/null 2>&1 || return 1
  command -v zip >/dev/null 2>&1 || return 1

  case "$target_format" in
    standard)
      [ $# -ge 3 ] || return 1
      new_w="$1"; new_h="$2"; new_fps="$3"
      ;;
    oneplus)
      [ $# -ge 5 ] || return 1
      new_w="$1"; new_h="$2"; new_ox="$3"; new_oy="$4"; new_fps="$5"
      ;;
    *)
      return 1
      ;;
  esac

  work_dir="$TMP_DIR/.desc-write.$$"
  rm -rf "$work_dir"
  mkdir -p "$work_dir" || return 1

  unzip -o -q "$zip_path" desc.txt -d "$work_dir" 2>/dev/null || {
    rm -rf "$work_dir"
    return 1
  }

  desc_file="$work_dir/desc.txt"
  [ -f "$desc_file" ] || {
    rm -rf "$work_dir"
    return 1
  }

  has_cr=no
  if grep -q "$(printf '\r')" "$desc_file" 2>/dev/null; then
    has_cr=yes
    tr -d '\r' < "$desc_file" > "$desc_file.lf"
    mv -f "$desc_file.lf" "$desc_file"
  fi

  case "$target_format" in
    standard)
      awk -v w="$new_w" -v h="$new_h" -v f="$new_fps" '
        BEGIN { done=0 }
        {
          if (!done && $0 !~ /^[[:space:]]*#/ && $0 !~ /^[[:space:]]*$/) {
            print w " " h " " f
            done=1
            next
          }
          print
        }
      ' "$desc_file" > "$desc_file.new" && mv -f "$desc_file.new" "$desc_file"
      ;;
    oneplus)
      awk -v w="$new_w" -v h="$new_h" -v ox="$new_ox" -v oy="$new_oy" -v f="$new_fps" '
        BEGIN { done=0 }
        {
          if (!done && $0 ~ /^[[:space:]]*g[[:space:]]+[0-9]+[[:space:]]+[0-9]+/) {
            print "g " w " " h " " ox " " oy " " f
            done=1
            next
          }
          print
        }
      ' "$desc_file" > "$desc_file.new" && mv -f "$desc_file.new" "$desc_file"
      ;;
    *)
      rm -rf "$work_dir"
      return 1
      ;;
  esac

  if [ "$has_cr" = "yes" ]; then
    awk '{ printf "%s\r\n", $0 }' "$desc_file" > "$desc_file.crlf" && mv -f "$desc_file.crlf" "$desc_file"
  fi

  ( cd "$work_dir" && zip -q "$zip_path" desc.txt ) 2>/dev/null || {
    rm -rf "$work_dir"
    return 1
  }

  rm -rf "$work_dir"
  return 0
}


# ========== 音频支持 ==========
AUDIO_STATE_FILE="$STATE_DIR/audio-mode"
AUDIO_LOG_FILE="$STATE_DIR/audio.log"

is_wav_file() {
  wav_path="$1"
  [ -f "$wav_path" ] || return 1
  # RIFF....WAVE
  magic=$(dd if="$wav_path" bs=12 count=1 2>/dev/null)
  case "$magic" in
    RIFF*WAVE*) return 0 ;;
    *) return 1 ;;
  esac
}

convert_to_wav() {
  src_path="$1"
  dst_path="$2"
  [ -f "$src_path" ] || return 1
  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -y -i "$src_path" -acodec pcm_s16le -ar 48000 -ac 2 "$dst_path" >/dev/null 2>&1
    [ -f "$dst_path" ] && return 0
  fi
  return 1
}

get_audio_mode() {
  if [ -f "$AUDIO_STATE_FILE" ]; then
    cat "$AUDIO_STATE_FILE" 2>/dev/null
  else
    echo "9plus"
  fi
}

set_audio_mode() {
  echo "$1" > "$AUDIO_STATE_FILE"
}

# 内嵌 audio.wav 到动画 zip
embed_audio_to_zip() {
  [ -n "$ZIP_BIN" ] || { echo "ERROR 设备缺少 zip 命令（内嵌音频不可用）"; return 1; }
  zip_path="$1"
  wav_path="$2"
  [ -f "$zip_path" ] || return 1
  [ -f "$wav_path" ] || return 1
  command -v unzip >/dev/null 2>&1 || return 1
  command -v zip >/dev/null 2>&1 || return 1

  work_dir="$TMP_DIR/.audio-embed.$$"
  rm -rf "$work_dir"
  mkdir -p "$work_dir" || return 1

  unzip -o -q "$zip_path" -d "$work_dir" 2>/dev/null || {
    rm -rf "$work_dir"
    return 1
  }

  # 把 audio.wav 放进每个 part 目录
  found_part=0
  for part_dir in "$work_dir"/part*; do
    [ -d "$part_dir" ] || continue
    cp -f "$wav_path" "$part_dir/audio.wav" 2>/dev/null && found_part=1
  done

  if [ "$found_part" = "0" ]; then
    # 没有 part 目录，放在根目录
    cp -f "$wav_path" "$work_dir/audio.wav" 2>/dev/null || {
      rm -rf "$work_dir"
      return 1
    }
  fi

  ( cd "$work_dir" && zip -rq -0 "$zip_path" . ) 2>/dev/null || {
    rm -rf "$work_dir"
    return 1
  }

  rm -rf "$work_dir"
  return 0
}


# ========== MIUI 音频安装 ==========
# 非 mp3 时：先尝试 ffmpeg 转 mp3，失败就重命名（改后缀）
prepare_miui_audio() {
  src_path="$1"
  dst_path="$2"
  [ -f "$src_path" ] || return 1

  # 已经是 mp3？
  case "$src_path" in
    *.mp3|*.MP3)
      cp -f "$src_path" "$dst_path" || return 1
      return 0
      ;;
  esac

  # 尝试 ffmpeg 转 mp3
  if command -v ffmpeg >/dev/null 2>&1; then
    if ffmpeg -y -i "$src_path" -codec:a libmp3lame -q:a 2 "$dst_path" >/dev/null 2>&1; then
      [ -f "$dst_path" ] && return 0
    fi
  fi

  # 转不了，直接重命名
  cp -f "$src_path" "$dst_path" || return 1
  return 0
}

install_miui_audio() {
  wav_path="$1"
  [ -f "$wav_path" ] || return 1

  target_dir="$MODDIR/system/product/media"
  target_file="$target_dir/bootaudio.mp3"
  mkdir -p "$target_dir" || return 1

  prepare_miui_audio "$wav_path" "$target_file" || return 1
  chmod 0644 "$target_file" 2>/dev/null
  return 0
}


# ========== 删除音频（三种模式全清） ==========
remove_audio_from_zip() {
  [ -n "$ZIP_BIN" ] || { echo "ERROR 设备缺少 zip 命令（删除音频不可用）"; return 1; }
  zip_path="$1"
  [ -f "$zip_path" ] || return 1
  command -v unzip >/dev/null 2>&1 || return 1
  command -v zip >/dev/null 2>&1 || return 1

  work_dir="$TMP_DIR/.audio-remove.$$"
  rm -rf "$work_dir"
  mkdir -p "$work_dir" || return 1

  unzip -o -q "$zip_path" -d "$work_dir" 2>/dev/null || {
    rm -rf "$work_dir"
    return 1
  }

  removed=0
  for part_dir in "$work_dir"/part*; do
    [ -d "$part_dir" ] || continue
    if [ -f "$part_dir/audio.wav" ]; then
      rm -f "$part_dir/audio.wav"
      removed=1
    fi
  done
  if [ -f "$work_dir/audio.wav" ]; then
    rm -f "$work_dir/audio.wav"
    removed=1
  fi

  if [ "$removed" = "0" ]; then
    rm -rf "$work_dir"
    return 0
  fi

  ( cd "$work_dir" && zip -rq -0 "$zip_path" . ) 2>/dev/null || {
    rm -rf "$work_dir"
    return 1
  }
  rm -rf "$work_dir"
  return 0
}

audio_remove_all() {
  removed_count=0

  # 1. Android 9+ 内嵌
  for entry_path in "$PAYLOAD_DIR"/*.zip "$PAYLOAD_LIBRARY_DIR"/*.zip; do
    [ -f "$entry_path" ] || continue
    [ "$entry_path" = "$PAYLOAD_FILE" ] && continue
    if remove_audio_from_zip "$entry_path"; then
      removed_count=$((removed_count + 1))
      echo "OK embed	$(payload_library_relative_path "$entry_path")"
    fi
  done
  if [ -f "$PAYLOAD_FILE" ]; then
    if remove_audio_from_zip "$PAYLOAD_FILE"; then
      removed_count=$((removed_count + 1))
      echo "OK embed	payload/bootanimation.zip"
    fi
  fi

  # 2. ≤ Android 9 挂载
  if [ -f "$PAYLOAD_DIR/bootaudio.wav" ]; then
    rm -f "$PAYLOAD_DIR/bootaudio.wav"
    removed_count=$((removed_count + 1))
    echo "OK mount	payload/bootaudio.wav"
  fi
  if [ -f "$MODDIR/post-fs-data-audio.sh" ]; then
    rm -f "$MODDIR/post-fs-data-audio.sh"
    removed_count=$((removed_count + 1))
    echo "OK mount	post-fs-data-audio.sh"
  fi

  # 3. MIUI
  if [ -f "$MODDIR/system/product/media/bootaudio.mp3" ]; then
    rm -f "$MODDIR/system/product/media/bootaudio.mp3"
    removed_count=$((removed_count + 1))
    echo "OK miui	system/product/media/bootaudio.mp3"
    rmdir "$MODDIR/system/product/media" 2>/dev/null
    rmdir "$MODDIR/system/product" 2>/dev/null
    rmdir "$MODDIR/system" 2>/dev/null
  fi

  # 4. 状态文件
  [ -f "$AUDIO_STATE_FILE" ] && rm -f "$AUDIO_STATE_FILE"

  record_status "webui-audio-remove"
  echo "SUMMARY removed=$removed_count"
  return 0
}
