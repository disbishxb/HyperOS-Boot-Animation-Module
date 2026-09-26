#!/system/bin/sh

MODDIR=${0%/*}
MODDIR=${MODDIR%/bin}
. "$MODDIR/bin/common.sh"

ensure_runtime_dirs

print_library() {
  entry_index=0
  active_source=$(selected_source_name)
  library_seen_reset

  for entry_path in "$PAYLOAD_DIR"/*.zip "$PAYLOAD_LIBRARY_DIR"/*.zip; do
    [ -f "$entry_path" ] || continue
    [ "$entry_path" = "$PAYLOAD_FILE" ] && continue
    library_entry_excluded "$entry_path" && continue
    entry_name=$(basename "$entry_path")
    if library_seen_has "$entry_name"; then
      continue
    fi
    library_seen_add "$entry_name"
    entry_index=$((entry_index + 1))
    entry_label_raw=$(payload_library_relative_path "$entry_path") || continue
    entry_label=$(printf '%s' "$entry_label_raw" | tr '\n\r\t' '___')
    entry_size=$(wc -c <"$entry_path" 2>/dev/null)
    entry_info=""
    if command -v unzip >/dev/null 2>&1; then
      entry_info=$(unzip -p "$entry_path" desc.txt 2>/dev/null | sed -n '1p' | awk '{print $1"×"$2" · "$3"fps"}')
    fi
    entry_active=no
    [ "$entry_label_raw" = "$active_source" ] && entry_active=yes
    printf '%s\t%s\t%s\t%s\t%s\n' "$entry_index" "$entry_label" "$entry_size" "$entry_active" "$entry_info"
  done
}

apply_selected_entry() {
  selected_index="$1"
  case "$selected_index" in
    ''|*[!0-9]*)
      echo "ERROR invalid animation index"
      return 1
      ;;
  esac

  selected_entry=$(payload_library_entry_at "$selected_index") || {
    echo "ERROR animation not found"
    return 1
  }
  selected_label=$(payload_library_relative_path "$selected_entry") || return 1

  activate_payload_from_path "$selected_entry" "$selected_label" || {
    echo "ERROR 动画应用失败，请重试或重新安装模块"
    return 1
  }
  clear_module_disabled
  refresh_overlay_tree || {
    echo "ERROR failed to refresh bootanimation overlay"
    return 1
  }
  deploy_bind_mounts >/dev/null 2>&1
  record_status "webui-select"
  echo "OK selected=$selected_label"
  return 0
}

safe_upload_name() {
  upload_name="$1"
  case "$upload_name" in
    ''|.*|*/*|*\\*|*..*|*[[:cntrl:]]*)
      return 1
      ;;
  esac

  upload_bytes=$(printf '%s' "$upload_name" | wc -c 2>/dev/null | tr -d ' ')
  [ -n "$upload_bytes" ] && [ "$upload_bytes" -le 80 ] || return 1

  case "$upload_name" in
    *.zip)
      ;;
    *.ZIP)
      upload_name="${upload_name%.*}.zip"
      ;;
    *)
      upload_name="$upload_name.zip"
      ;;
  esac

  printf '%s\n' "$upload_name"
}

import_uploaded_entry() {
  staged_path="$1"
  requested_name="$2"

  case "$staged_path" in
    "$TMP_DIR"/upload-*.zip)
      ;;
    *)
      echo "ERROR invalid upload staging path"
      return 1
      ;;
  esac
  [ -f "$staged_path" ] || {
    echo "ERROR uploaded file is missing"
    return 1
  }

  upload_name=$(safe_upload_name "$requested_name") || {
    echo "ERROR invalid file name"
    return 1
  }
  is_bootanimation_archive "$staged_path" || {
    rm -f "$staged_path"
    echo "ERROR 不是有效的开机动画 zip（需要是 ZIP 格式，且根目录包含 desc.txt）"
    return 1
  }

  upload_name=$(unique_library_target "$upload_name")
  target_path="$PAYLOAD_LIBRARY_DIR/$upload_name"

  mv -f "$staged_path" "$target_path" || {
    echo "ERROR failed to store uploaded archive"
    return 1
  }
  chmod 0644 "$target_path" 2>/dev/null
  target_label=$(payload_library_relative_path "$target_path") || return 1

  record_status "webui-upload"
  echo "OK stored=$target_label"
  return 0
}

run_import_local() {
  source_path="$1"
  [ -n "$source_path" ] || {
    echo "ERROR empty source path"
    return 1
  }
  [ -f "$source_path" ] || {
    echo "ERROR file not found: $source_path"
    return 1
  }

  is_bootanimation_archive "$source_path" || {
    echo "ERROR 不是有效的开机动画 zip（需要是 ZIP 格式，且根目录包含 desc.txt）"
    return 1
  }

  source_base=$(basename "$source_path")
  upload_name=$(safe_upload_name "$source_base") || upload_name="bootanimation-local.zip"
  upload_name=$(unique_library_target "$upload_name")
  target_path="$PAYLOAD_LIBRARY_DIR/$upload_name"

  import_tmp="$TMP_DIR/.import-local.$$.tmp"
  if cp -fp "$source_path" "$import_tmp" 2>/dev/null && mv -f "$import_tmp" "$target_path" 2>/dev/null; then
    :
  else
    rm -f "$import_tmp"
    echo "ERROR failed to copy file"
    return 1
  fi
  chmod 0644 "$target_path" 2>/dev/null

  target_label=$(payload_library_relative_path "$target_path") || {
    rm -f "$target_path"
    echo "ERROR failed to resolve library path"
    return 1
  }

  record_status "webui-import-local"
  echo "OK stored=$target_label"
  return 0
}

import_local_entry() {
  set_import_busy || {
    echo "ERROR cannot mark import busy"
    return 1
  }

  result_tmp="$TMP_DIR/.last-import.$$.tmp"
  rm -f "$result_tmp"
  run_import_local "$1" >"$result_tmp" 2>&1
  run_status=$?

  mv -f "$result_tmp" "$LAST_IMPORT_FILE" 2>/dev/null
  clear_import_busy
  cat "$LAST_IMPORT_FILE" 2>/dev/null
  return "$run_status"
}

delete_library_entry() {
  selected_index="$1"
  case "$selected_index" in
    ''|*[!0-9]*)
      echo "ERROR 动画编号无效"
      return 1
      ;;
  esac

  selected_entry=$(payload_library_entry_at "$selected_index") || {
    echo "ERROR 动画不存在"
    return 1
  }
  selected_label=$(payload_library_relative_path "$selected_entry") || return 1

  case "$selected_entry" in
    "$PAYLOAD_DIR"/*/*)
      # 导入的动画（payload/animations/ 等子目录），允许删除
      ;;
    "$PAYLOAD_DIR"/*)
      echo "ERROR 内置动画不能删除（防止误删默认动画）；导入的动画可以删除"
      return 1
      ;;
  esac

  if [ "$selected_label" = "$(selected_source_name)" ]; then
    echo "ERROR 该动画正在使用中，请先切换其他动画再删除"
    return 1
  fi

  rm -f "$selected_entry" 2>/dev/null || {
    echo "ERROR 删除失败"
    return 1
  }
  echo "OK deleted=$selected_label"
  return 0
}

reset_to_default() {
  default_source_path="$MODDIR/$DEFAULT_SOURCE_NAME"
  if [ ! -f "$default_source_path" ]; then
    echo "ERROR 默认动画不存在"
    return 1
  fi

  clear_module_disabled
  activate_payload_from_path "$default_source_path" "$DEFAULT_SOURCE_NAME" || {
    echo "ERROR 恢复默认动画失败"
    return 1
  }
  refresh_overlay_tree || {
    echo "ERROR 刷新覆盖失败"
    return 1
  }
  deploy_bind_mounts >/dev/null 2>&1
  record_status "webui-reset"
  echo "OK selected=$DEFAULT_SOURCE_NAME"
  return 0
}

case "$1" in
  list)
    print_library
    ;;
  status)
    echo "selected_source=$(selected_source_name)"
    echo "payload_size=$(payload_size_bytes)"
    echo "module_disabled=$(module_disabled && echo yes || echo no)"
    echo "import_busy=$(import_busy_active && echo yes || echo no)"
    echo "last_import=$(cat "$LAST_IMPORT_FILE" 2>/dev/null)"
    echo "available_animations=$(payload_library_count)"
    echo "play_mode=$(get_play_mode)"
    echo "language=$(get_language)"
    ;;
  select)
    apply_selected_entry "$2"
    ;;
  import)
    import_uploaded_entry "$2" "$3"
    ;;
  import-local)
    import_local_entry "$2"
    ;;
  delete)
    delete_library_entry "$2"
    ;;
  reset)
    reset_to_default
    ;;
  verify)
    builtin_payload_status
    ;;
  enable)
    clear_module_disabled
    refresh_overlay_tree || {
      echo "ERROR 刷新覆盖失败"
      exit 1
    }
    deploy_bind_mounts >/dev/null 2>&1
    record_status "webui-enable"
    echo "OK enabled"
    ;;
  disable)
    set_module_disabled
    for target_path in $(device_target_paths); do
      [ -n "$target_path" ] || continue
      if grep -F " $target_path " /proc/self/mountinfo >/dev/null 2>&1; then
        umount "$target_path" 2>/dev/null
      fi
    done
    record_status "webui-disable"
    echo "OK disabled"
    ;;
  play-mode-get)
    get_play_mode
    ;;
  play-mode-set)
    if [ -z "$2" ]; then
      echo "ERROR 请指定模式：off / random / sequential"
      exit 1
    fi
    case "$2" in
      off|random|sequential)
        set_play_mode "$2"
        echo "OK play mode set to $2"
        ;;
      *)
        echo "ERROR 无效模式，可选：off / random / sequential"
        exit 1
        ;;
    esac
    ;;
  language-get)
    get_language
    ;;
  language-set)
    if [ -z "$2" ]; then
      echo "ERROR 请指定语言：zh 或 en"
      exit 1
    fi
    case "$2" in
      zh|en)
        set_language "$2"
        echo "OK language set to $2"
        ;;
      *)
        echo "ERROR 无效语言，可选：zh / en"
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Usage: $0 {list|status|select INDEX|delete INDEX|reset|verify|import STAGED_FILE SAFE_NAME|import-local PATH|enable|disable|play-mode-get|play-mode-set off/random/sequential|language-get|language-set zh/en}"
    exit 64
    ;;
esac