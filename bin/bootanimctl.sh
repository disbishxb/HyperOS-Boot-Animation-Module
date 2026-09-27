#!/system/bin/sh

MODDIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$MODDIR/bin/common.sh"

ensure_runtime_dirs

# ========== 动画库列表 ==========
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
      desc_tmp="$TMP_DIR/.desc.$$.txt"
      unzip -p "$entry_path" desc.txt >"$desc_tmp" 2>/dev/null
      format=$(detect_desc_format "$desc_tmp")
      case "$format" in
        standard)
          geom=$(parse_desc_standard "$desc_tmp")
          if [ -n "$geom" ]; then
            set -- $geom
            entry_info="${1}×${2} · ${3}fps"
          fi
          ;;
        oneplus)
          geom=$(parse_desc_oneplus "$desc_tmp")
          if [ -n "$geom" ]; then
            set -- $geom
            entry_info="${1}×${2} · ${5}fps"
          fi
          ;;
      esac
      rm -f "$desc_tmp"
    fi
    entry_active=no
    [ "$entry_label_raw" = "$active_source" ] && entry_active=yes
    printf '%s\t%s\t%s\t%s\t%s\n' "$entry_index" "$entry_label" "$entry_size" "$entry_active" "$entry_info"
  done
}

# ========== 应用选中动画 ==========
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

# ========== 上传名过滤 ==========
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

# ========== 导入上传 ==========
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

# ========== 本地导入 ==========
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

# ========== 删除 ==========
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

# ========== 恢复默认 ==========
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

# ========== 改分辨率：读单个动画 ==========
desc_get_entry() {
  zip_path="$1"
  [ -f "$zip_path" ] || { echo "ERROR file not found"; return 1; }
  result=$(read_desc_geometry_from_zip "$zip_path") || { echo "ERROR cannot read desc.txt"; return 1; }
  echo "OK $result"
  return 0
}

# ========== 改分辨率：读原厂备份 ==========
desc_get_original() {
  result=$(read_original_geometry) || {
    echo "ERROR 原厂备份不存在或无法读取"
    return 1
  }
  source_path=""
  [ -f "$ORIGINAL_SOURCE" ] && source_path=$(cat "$ORIGINAL_SOURCE" 2>/dev/null)
  echo "OK $result"
  echo "source=$source_path"
  return 0
}

# ========== 改分辨率：单动画改写 ==========
# 用法：
#   desc-set ZIP standard W H FPS
#   desc-set ZIP oneplus W H OX OY FPS
desc_set_entry() {
  zip_path="$1"
  target_format="$2"
  shift 2

  [ -f "$zip_path" ] || { echo "ERROR file not found"; return 1; }

  case "$target_format" in
    standard)
      [ $# -ge 3 ] || { echo "ERROR missing arguments"; return 1; }
      new_w="$1"; new_h="$2"; new_fps="$3"
      ;;
    oneplus)
      [ $# -ge 5 ] || { echo "ERROR missing arguments"; return 1; }
      new_w="$1"; new_h="$2"; new_ox="$3"; new_oy="$4"; new_fps="$5"
      ;;
    *)
      echo "ERROR invalid format"; return 1
      ;;
  esac

  for v in "$new_w" "$new_h" "$new_fps"; do
    case "$v" in ''|*[!0-9]*) echo "ERROR invalid number"; return 1;; esac
  done
  if [ "$target_format" = "oneplus" ]; then
    for v in "$new_ox" "$new_oy"; do
      case "$v" in ''|*[!0-9]*) echo "ERROR invalid offset"; return 1;; esac
    done
  fi

  desc_tmp="$TMP_DIR/.desc-fmt.$$.txt"
  unzip -p "$zip_path" desc.txt >"$desc_tmp" 2>/dev/null
  actual_format=$(detect_desc_format "$desc_tmp")
  rm -f "$desc_tmp"

  if [ "$actual_format" = "unknown" ]; then
    echo "ERROR 无法识别 desc.txt 格式"
    return 1
  fi

  if [ "$actual_format" != "$target_format" ]; then
    echo "ERROR 格式不匹配：实际为 $actual_format，配置为 $target_format"
    return 1
  fi

  backup_desc_to_bak "$zip_path" || {
    echo "ERROR 备份 desc.txt 失败"
    return 1
  }

  if [ "$target_format" = "oneplus" ]; then
    write_desc_geometry_to_zip "$zip_path" "$target_format" "$new_w" "$new_h" "$new_ox" "$new_oy" "$new_fps" || {
      echo "ERROR 写入 desc.txt 失败"
      return 1
    }
  else
    write_desc_geometry_to_zip "$zip_path" "$target_format" "$new_w" "$new_h" "$new_fps" || {
      echo "ERROR 写入 desc.txt 失败"
      return 1
    }
  fi

  echo "OK changed=$zip_path"
  return 0
}

# ========== 改分辨率：单动画恢复 ==========
desc_restore_entry() {
  zip_path="$1"
  [ -f "$zip_path" ] || { echo "ERROR file not found"; return 1; }

  restore_desc_from_bak "$zip_path" || {
    echo "ERROR 恢复失败（备份不存在或 zip 更新失败）"
    return 1
  }
  echo "OK restored=$zip_path"
  return 0
}

# ========== 改分辨率：批量应用配置 ==========
apply_config_to_entries() {
  config_name="$1"
  force="$2"
  shift 2
  # 剩余参数是动画相对路径列表

  cfg="$(config_path "$config_name")"
  [ -f "$cfg" ] || { echo "ERROR config not found"; return 1; }

  format=$(grep '^format=' "$cfg" | head -n1 | sed 's/^format=//')
  width=$(grep '^width=' "$cfg" | head -n1 | sed 's/^width=//')
  height=$(grep '^height=' "$cfg" | head -n1 | sed 's/^height=//')
  fps=$(grep '^fps=' "$cfg" | head -n1 | sed 's/^fps=//')

  if [ "$format" = "oneplus" ]; then
    offsetx=$(grep '^offsetx=' "$cfg" | head -n1 | sed 's/^offsetx=//')
    offsety=$(grep '^offsety=' "$cfg" | head -n1 | sed 's/^offsety=//')
  fi

  changed_paths=""
  success_count=0
  skip_count=0

  for rel_path in "$@"; do
    [ -n "$rel_path" ] || continue
    zip_path="$MODDIR/$rel_path"
    [ -f "$zip_path" ] || {
      echo "SKIP	$rel_path	file not found"
      skip_count=$((skip_count + 1))
      continue
    }

    desc_tmp="$TMP_DIR/.desc-apply.$$.txt"
    unzip -p "$zip_path" desc.txt >"$desc_tmp" 2>/dev/null
    actual_format=$(detect_desc_format "$desc_tmp")
    rm -f "$desc_tmp"

    # unknown 永远跳过（即使 force）
    if [ "$actual_format" = "unknown" ]; then
      echo "SKIP	$rel_path	unknown format"
      skip_count=$((skip_count + 1))
      continue
    fi

    # 非 force 模式：格式不匹配跳过
    if [ "$force" != "force" ] && [ "$actual_format" != "$format" ]; then
      echo "SKIP	$rel_path	format mismatch (actual=$actual_format config=$format)"
      skip_count=$((skip_count + 1))
      continue
    fi

    backup_desc_to_bak "$zip_path" || {
      echo "SKIP	$rel_path	backup failed"
      skip_count=$((skip_count + 1))
      continue
    }

    if [ "$format" = "oneplus" ]; then
      write_desc_geometry_to_zip "$zip_path" "$format" "$width" "$height" "$offsetx" "$offsety" "$fps"
      write_status=$?
    else
      write_desc_geometry_to_zip "$zip_path" "$format" "$width" "$height" "$fps"
      write_status=$?
    fi

    if [ "$write_status" -eq 0 ]; then
      echo "OK	$rel_path"
      changed_paths="$changed_paths $rel_path"
      success_count=$((success_count + 1))
    else
      echo "SKIP	$rel_path	write failed"
      skip_count=$((skip_count + 1))
    fi
  done

  if [ -n "$changed_paths" ]; then
    # shellcheck disable=SC2086
    record_undo "apply-config" $changed_paths
  fi

  echo "SUMMARY success=$success_count skip=$skip_count"
  return 0
}

# ========== 音频导入 ==========
# 用法：audio-import STAGED_FILE MODE PATH1 PATH2 ...
#   MODE: 9plus / 9minus
audio_import_entry() {
  staged="$1"
  mode="$2"
  shift 2
  # 剩下的是动画相对路径

  [ -f "$staged" ] || { echo "ERROR staged file missing"; return 1; }

  # MIUI 模式：直接安装到 system/product/media/bootaudio.mp3
  if [ "$mode" = "miui" ]; then
    if install_miui_audio "$staged"; then
      set_audio_mode "miui"
      rm -f "$staged" 2>/dev/null
      record_status "webui-audio-miui"
      echo "OK miui audio installed"
      return 0
    else
      echo "ERROR miui audio install failed"
      return 1
    fi
  fi

  # 非 WAV：尝试转换
  if ! is_wav_file "$staged"; then
    wav_tmp="${staged%.*}.wav"
    if convert_to_wav "$staged" "$wav_tmp"; then
      mv -f "$wav_tmp" "$staged"
    else
      echo "ERROR 非 WAV 格式，且设备无 ffmpeg，请先转成 WAV"
      return 1
    fi
  fi

  # 保存模式
  set_audio_mode "$mode"

  success_count=0
  skip_count=0

  if [ "$mode" = "9plus" ]; then
    # 内嵌到每个动画 zip
    for rel_path in "$@"; do
      [ -n "$rel_path" ] || continue
      zip_path="$MODDIR/$rel_path"
      [ -f "$zip_path" ] || {
        echo "SKIP\t$rel_path\tfile not found"
        skip_count=$((skip_count + 1))
        continue
      }
      if embed_audio_to_zip "$zip_path" "$staged"; then
        echo "OK\t$rel_path"
        success_count=$((success_count + 1))
      else
        echo "SKIP\t$rel_path\tembed failed"
        skip_count=$((skip_count + 1))
      fi
    done
  else
    # ≤ Android 9：把 wav 存到 payload 目录，写挂载脚本
    target_wav="$PAYLOAD_DIR/bootaudio.wav"
    cp -f "$staged" "$target_wav" || {
      echo "ERROR failed to store audio"
      return 1
    }
    chmod 0644 "$target_wav" 2>/dev/null

    # 写挂载脚本
    audio_mount="$MODDIR/post-fs-data-audio.sh"
    cat > "$audio_mount" <<'AUDIOEOF'
#!/system/bin/sh
# 由 audio-import 自动生成，勿手动改
sdk=$(getprop ro.build.version.sdk)
if [ "$sdk" -lt 28 ]; then
  MODDIR=${0%/*}
  music="$MODDIR/payload/bootaudio.wav"
  [ -f "$music" ] || exit 0
  for target in /system/media/bootaudio.mp3 /system/product/media/bootaudio.mp3 /product/media/bootaudio.mp3; do
    if [ -e "$target" ]; then
      mount --bind "$music" "$target" 2>>"$MODDIR/var/state/audio.log"
      echo "$(date '+%Y-%m-%d %H:%M:%S') mount $music -> $target" >> "$MODDIR/var/state/audio.log"
    fi
  done
fi
AUDIOEOF
    chmod 0755 "$audio_mount"

    for rel_path in "$@"; do
      [ -n "$rel_path" ] || continue
      echo "OK\t$rel_path"
      success_count=$((success_count + 1))
    done
  fi

  record_status "webui-audio-import"
  echo "SUMMARY success=$success_count skip=$skip_count"
  return 0
}

# ========== 撤销 ==========
do_undo() {
  has_undo || { echo "ERROR 没有可撤销的操作"; return 1; }
  apply_undo || { echo "ERROR 撤销失败"; return 1; }
  echo "OK undone"
  return 0
}

# ========== 命令分发 ==========
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
    echo "theme=$(get_theme)"
    echo "brand=$(get_brand)"
    if has_undo; then
      echo "has_undo=yes"
    else
      echo "has_undo=no"
    fi
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
        update_module_prop_description "$(selected_display_name)"
        echo "OK language set to $2"
        ;;
      *)
        echo "ERROR 无效语言，可选：zh / en"
        exit 1
        ;;
    esac
    ;;
  theme-get)
    get_theme
    ;;
  theme-set)
    if [ -z "$2" ]; then
      echo "ERROR 请指定主题：light 或 dark"
      exit 1
    fi
    case "$2" in
      light|dark)
        set_theme "$2"
        echo "OK theme set to $2"
        ;;
      *)
        echo "ERROR 无效主题，可选：light / dark"
        exit 1
        ;;
    esac
    ;;
  desc-get)
    desc_get_entry "$2"
    ;;
  desc-original)
    desc_get_original
    ;;
  desc-set)
    shift
    desc_set_entry "$@"
    ;;
  desc-restore)
    desc_restore_entry "$2"
    ;;
  modified-list)
    list_modified_animations
    ;;
  config-list)
    config_list
    ;;
  config-save)
    shift
    config_save "$@"
    case $? in
      0) echo "OK saved=$1" ;;
      2) echo "ERROR 配置名已存在" ;;
      *) echo "ERROR 无效配置名或参数" ;;
    esac
    ;;
  config-delete)
    config_delete "$2" || { echo "ERROR 配置不存在"; exit 1; }
    echo "OK deleted=$2"
    ;;
  apply-config)
    config_name="$2"
    force="$3"
    shift 3
    apply_config_to_entries "$config_name" "$force" "$@"
    ;;
  undo)
    do_undo
    ;;
  audio-import)
    shift
    audio_import_entry "$@"
    ;;
  audio-remove)
    audio_remove_all
    ;;
  tool-status)
    echo "zip=$([ -n "$ZIP_BIN" ] && echo yes || echo no)"
    echo "zip_path=$ZIP_BIN"
    echo "unzip=$([ -n "$UNZIP_BIN" ] && echo yes || echo no)"
    echo "unzip_path=$UNZIP_BIN"
    echo "ffmpeg=$([ -n "$FFMPEG_BIN" ] && echo yes || echo no)"
    echo "ffmpeg_path=$FFMPEG_BIN"
    ;;
  audio-status)
    # 三种模式检测
    miui_file="$MODDIR/system/product/media/bootaudio.mp3"
    mount_file="$PAYLOAD_DIR/bootaudio.wav"

    audio_present=no
    audio_file=""
    audio_size=0
    audio_mode=$(get_audio_mode)

    # 优先级：MIUI > 挂载 > 内嵌
    if [ -f "$miui_file" ]; then
      audio_present=yes
      audio_file=system/product/media/bootaudio.mp3
      audio_size=$(wc -c < "$miui_file" 2>/dev/null | tr -d ' ')
      audio_mode=miui
    elif [ -f "$mount_file" ]; then
      audio_present=yes
      audio_file=payload/bootaudio.wav
      audio_size=$(wc -c < "$mount_file" 2>/dev/null | tr -d ' ')
      [ "$audio_mode" = "9plus" ] && audio_mode=9minus
    fi

    echo "audio_present=$audio_present"
    echo "audio_file=$audio_file"
    echo "audio_size=$audio_size"
    echo "audio_mode=$audio_mode"
    echo "audio_sdk=$(getprop ro.build.version.sdk 2>/dev/null)"
    if [ -f "$miui_file" ]; then
      echo "audio_valid=yes"
    elif [ -f "$mount_file" ] && is_wav_file "$mount_file"; then
      echo "audio_valid=yes"
    else
      echo "audio_valid=no"
    fi
    if grep -q 'bootaudio' /proc/self/mountinfo 2>/dev/null; then
      echo "audio_mounted=yes"
    else
      echo "audio_mounted=no"
    fi
    ;;
  audio-mode-get)
    get_audio_mode
    ;;
  audio-mode-set)
    set_audio_mode "$2"
    echo "OK audio mode set to $2"
    ;;
  *)
    echo "Usage: $0 {list|status|select INDEX|delete INDEX|reset|import STAGED_FILE SAFE_NAME|import-local PATH|enable|disable|play-mode-get|play-mode-set off/random/sequential|language-get|language-set zh/en|theme-get|theme-set light/dark|desc-get ZIP|desc-original|desc-set ZIP FORMAT W H [OX OY] FPS|desc-restore ZIP|modified-list|config-list|config-save NAME FORMAT W H [OX OY] FPS|config-delete NAME|apply-config NAME normal/force PATH...|undo}"
    exit 64
    ;;
esac
