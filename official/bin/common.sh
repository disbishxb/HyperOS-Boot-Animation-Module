#!/system/bin/sh

: "${MODDIR:=${0%/*}}"

MODID=hyperosbootanim
DEFAULT_SOURCE_NAME="payload/MIUI粒子效果.zip"
MODULE_BASE_DESCRIPTION="免改分区替换HyperOS开机动画"
PAYLOAD_DIR="$MODDIR/payload"
PAYLOAD_FILE="$PAYLOAD_DIR/bootanimation.zip"
PAYLOAD_LIBRARY_DIR="$PAYLOAD_DIR/animations"
STATE_DIR="$MODDIR/var/state"
STATUS_FILE="$STATE_DIR/status.txt"
TMP_DIR="$MODDIR/var/tmp"
OVERLAY_META_FILE="$STATE_DIR/overlay-tree.meta"
SELECTED_SOURCE_FILE="$STATE_DIR/selected_animation.txt"
MODULE_DISABLED_FILE="$STATE_DIR/disabled"
IMPORT_BUSY_FILE="$STATE_DIR/import-busy"
LAST_IMPORT_FILE="$STATE_DIR/last-import.txt"
LANGUAGE_FILE="$STATE_DIR/language"

# ========== 更多播放功能 ==========
PLAY_MODE_FILE="$STATE_DIR/play_mode"
SEQUENTIAL_INDEX_FILE="$STATE_DIR/sequential_index"

ensure_runtime_dirs() {
  mkdir -p "$PAYLOAD_DIR" "$PAYLOAD_LIBRARY_DIR" "$STATE_DIR" "$TMP_DIR" 2>/dev/null
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

# ========== 更多播放功能 ==========
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

# ========== 原有函数 ==========

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

is_bootanimation_archive() {
  archive_path="$1"

  if [ ! -s "$archive_path" ]; then
    return 1
  fi

  magic=$(dd if="$archive_path" bs=2 count=1 2>/dev/null)
  if [ "$magic" != "PK" ]; then
    return 1
  fi

  if command -v unzip >/dev/null 2>&1; then
    if ! unzip -l "$archive_path" 2>/dev/null | grep -q 'desc\.txt'; then
      return 1
    fi
  fi

  return 0
}

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

builtin_payload_manifest() {
  cat <<'EOF'
MIUI粒子效果.zip 121428970
EOF
}

builtin_payload_status() {
  builtin_payload_manifest | while read -r manifest_name manifest_size; do
    [ -n "$manifest_name" ] || continue
    actual_size=0
    if [ -f "$PAYLOAD_DIR/$manifest_name" ]; then
      actual_size=$(wc -c <"$PAYLOAD_DIR/$manifest_name" 2>/dev/null)
    fi
    if [ "$actual_size" = "$manifest_size" ]; then
      echo "OK $manifest_name $actual_size"
    else
      echo "BAD $manifest_name expected=$manifest_size actual=$actual_size"
    fi
  done
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

update_module_prop_description() {
  prop_value="$1"
  [ -f "$MODDIR/module.prop" ] || return 0
  ensure_runtime_dirs
  prop_tmp="$TMP_DIR/.module.prop.$$.tmp"
  new_desc="当前生效动画：$prop_value。$MODULE_BASE_DESCRIPTION"
  awk -v nd="$new_desc" 'BEGIN { FS = OFS = "=" } $1 == "description" { print "description=" nd; next } { print }' "$MODDIR/module.prop" >"$prop_tmp" 2>/dev/null || return 1
  mv -f "$prop_tmp" "$MODDIR/module.prop" 2>/dev/null || return 1
  return 0
}

set_selected_source_name() {
  selected_source_name_value="$1"
  selected_source_tmp="$TMP_DIR/.selected_animation.$$.tmp"
  printf '%s\n' "$selected_source_name_value" >"$selected_source_tmp" || return 1
  mv -f "$selected_source_tmp" "$SELECTED_SOURCE_FILE" || return 1
}

module_disabled() {
  [ -f "$MODULE_DISABLED_FILE" ]
}

set_module_disabled() {
  ensure_runtime_dirs
  : >"$MODULE_DISABLED_FILE" 2>/dev/null || return 1
  return 0
}

clear_module_disabled() {
  rm -f "$MODULE_DISABLED_FILE"
}

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

activate_payload_from_path() {
  source_path="$1"
  source_label="$2"
  active_payload_tmp="$TMP_DIR/.bootanimation.zip.$$.tmp"

  is_bootanimation_archive "$source_path" || {
    return 1
  }

  if [ "$source_label" = "$(selected_source_name)" ] && [ -f "$PAYLOAD_FILE" ]; then
    update_module_prop_description "$(selected_display_name)"
    return 0
  fi

  rm -f "$active_payload_tmp" 2>/dev/null
  cp -fp "$source_path" "$active_payload_tmp" 2>/dev/null || {
    return 1
  }
  chmod 0644 "$active_payload_tmp" 2>/dev/null

  rm -f "$PAYLOAD_FILE" 2>/dev/null
  if mv -f "$active_payload_tmp" "$PAYLOAD_FILE" 2>/dev/null; then
    :
  else
    if ! cp -fp "$active_payload_tmp" "$PAYLOAD_FILE" 2>/dev/null; then
      rm -f "$active_payload_tmp" 2>/dev/null
      return 1
    fi
    rm -f "$active_payload_tmp" 2>/dev/null
  fi

  if set_selected_source_name "$source_label"; then
    :
  else
    printf '%s\n' "$source_label" >"$SELECTED_SOURCE_FILE" 2>/dev/null || {
      return 1
    }
  fi

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
      is_bootanimation_archive "$imported_tmp" || {
        rm -f "$imported_tmp"
        return 1
      }
      mv -f "$imported_tmp" "$imported_file" || return 1
      chmod 0644 "$imported_file" 2>/dev/null
      activate_payload_from_path "$imported_file" "payload/animations/imported-external.zip" || return 1
      echo "$source_path" >"$STATE_DIR/last_import_source.txt"
      return 0
    fi
  done

  return 1
}

prepare_payload() {
  if module_disabled; then
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

  return 1
}

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

module_target_paths() {
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

refresh_overlay_tree() {
  prepare_payload || return 1

  rm -rf "$MODDIR/system"

  for rel_path in $(module_target_paths); do
    [ -n "$rel_path" ] || continue
    dst="$MODDIR/$rel_path"
    mkdir -p "${dst%/*}" 2>/dev/null || return 1
    if ! ln -f "$PAYLOAD_FILE" "$dst" 2>/dev/null; then
      cp -fp "$PAYLOAD_FILE" "$dst" 2>/dev/null || return 1
    fi
    chmod 0644 "$dst" 2>/dev/null
  done

  payload_fingerprint >"$OVERLAY_META_FILE"

  return 0
}

ensure_overlay_tree() {
  if overlay_tree_current; then
    return 0
  fi

  refresh_overlay_tree
}

device_target_paths() {
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

  target_exists_or_wait "$target_path" || {
    return 1
  }

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
    bind_mount_target "$target_path"
  done
}

record_status() {
  ensure_runtime_dirs
  stage_name="$1"
  prop_path=$(getprop ro.product.bootanim.file 2>/dev/null)

  {
    echo "stage=$stage_name"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "android_release=$(getprop ro.build.version.release 2>/dev/null)"
    echo "sdk=$(getprop ro.build.version.sdk 2>/dev/null)"
    echo "hyperos_version=$(getprop ro.mi.os.version.name 2>/dev/null)"
    echo "hyperos_incremental=$(getprop ro.system.build.version.incremental 2>/dev/null)"
    echo "product_bootanim_property=$prop_path"
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
    echo "play_mode=$(get_play_mode)"
    echo "language=$(get_language)"
    echo "bind_mounts:"
    grep -E '/bootanimation\.zip' /proc/self/mountinfo 2>/dev/null | sed 's/^/  /'
    echo "candidate_targets:"
    device_target_paths | sed 's/^/  - /'
  } >"$STATUS_FILE"
}