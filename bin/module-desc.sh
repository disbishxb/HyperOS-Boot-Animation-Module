#!/system/bin/sh
# ============================================================
# module-desc.sh
# 按当前语言 + 当前动画名，更新 module.prop 的 name 和 description
# 由 bootanimctl.sh 调用，不暴露给模块管理器
# ============================================================

MODDIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$MODDIR/bin/common.sh"

ensure_runtime_dirs

prop_value="${1:-$(selected_display_name)}"
[ -n "$prop_value" ] || prop_value="—"

[ -f "$MODDIR/module.prop" ] || {
  echo "ERROR module.prop not found"
  exit 1
}

lang=$(get_language)

if [ "$lang" = "en" ]; then
  new_name="$MODULE_NAME_EN"
  new_desc="Active: $prop_value. $MODULE_BASE_DESCRIPTION_EN"
else
  new_name="$MODULE_NAME_ZH"
  new_desc="当前生效动画：$prop_value。$MODULE_BASE_DESCRIPTION"
fi

prop_tmp="$TMP_DIR/.module.prop.$$.tmp"

awk -v nn="$new_name" -v nd="$new_desc" '
  BEGIN { FS = OFS = "=" }
  $1 == "name"        { print "name=" nn; next }
  $1 == "description" { print "description=" nd; next }
  { print }
' "$MODDIR/module.prop" >"$prop_tmp" 2>/dev/null || {
  rm -f "$prop_tmp"
  echo "ERROR awk failed"
  exit 1
}

mv -f "$prop_tmp" "$MODDIR/module.prop" 2>/dev/null || {
  rm -f "$prop_tmp"
  echo "ERROR mv failed"
  exit 1
}

echo "OK name=$new_name desc=$new_desc"
