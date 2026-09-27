#!/system/bin/sh
# ============================================================
# payload/pack.sh
# 把 payload/ 下的动画目录打成 zip，供 build.sh 使用
# 用法：bash payload/pack.sh
# ============================================================

set -e

PAYLOAD_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PAYLOAD_DIR"

echo "=================================================="
echo " 打包 payload 动画目录 → zip"
echo " 目录：$PAYLOAD_DIR"
echo "=================================================="
echo ""

command -v zip >/dev/null 2>&1 || { echo "❌ 需要 zip：pkg install zip"; exit 1; }

# 找所有"目录"（排除 animations/ backups/）
FOUND=0
for dir in */; do
  dir="${dir%/}"

  # 跳过内部目录
  case "$dir" in
    animations|backups) continue ;;
  esac

  # 目录里必须有 desc.txt 才是有效动画
  if [ ! -f "$dir/desc.txt" ]; then
    echo "⏭  跳过 $dir（没有 desc.txt）"
    continue
  fi

  target_zip="$dir.zip"

  if [ -f "$target_zip" ]; then
    echo "⏭  $target_zip 已存在，跳过"
    continue
  fi

  echo "📦 正在打包：$dir → $target_zip"
  ( cd "$dir" && zip -rq "../$target_zip" . ) || {
    echo "   ❌ 打包失败：$dir"
    continue
  }
  size=$(du -h "$target_zip" | cut -f1)
  echo "   ✅ 完成：$target_zip ($size)"
  FOUND=$((FOUND + 1))
done

echo ""
if [ "$FOUND" -eq 0 ]; then
  echo "⚠️  没有打包任何东西（可能目录里没有 desc.txt，或 zip 已存在）"
else
  echo "✅ 打包了 $FOUND 个动画"
fi
echo ""
echo "下一步："
echo "  cd .."
echo "  bash build.sh"