#!/system/bin/sh
# ============================================================
#  HyperOS-Boot-Animation-Module 打包工具 v2.0
#  风格：圆框标题 + 方向键选择 + 杂鱼工具箱吐槽味
#  用法：sh build.sh
# ============================================================

if [ -z "$BASH_VERSION" ]; then
    command -v bash >/dev/null 2>&1 && exec bash "$0" "$@"
    [ -x /system/bin/bash ] && exec /system/bin/bash "$0" "$@"
    echo "❌ 需要 bash，请先 pkg install bash"
    exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
STAMP="$(date +%Y%m%d-%H%M%S)"

# ---------- 杂鱼配色 ----------
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
PURPLE='\033[1;35m'
PINK='\033[1;35m'
ORANGE='\033[1;91m'
GOLD='\033[1;33m'
GRAY='\033[38;5;245m'
DIM='\033[2m'
RESET='\033[0m'
BOLD='\033[1m'

BG_SELECT='\033[48;5;46m'
FG_SELECT='\033[97m'
BOLD_SELECT='\033[1m'

# ---------- 前置检查 ----------
if ! command -v zip >/dev/null 2>&1; then
    echo -e "${RED}❌ 缺少 zip 命令，请先安装：pkg install zip${RESET}"
    exit 1
fi

# ============================================================
#  圆框标题（保留原样）
# ============================================================
LINE="〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓"

show_ui() {
    printf '\033[H\033[2J'
    printf '%b\n' \
        "${PINK}" \
        "    ╭───────────────────────────────────────╮" \
        "    │      🎮 小杂鱼的模块打包工具 🎮       │" \
        "    │              build v2.0               │" \
        "    ╰───────────────────────────────────────╯" \
        "${RESET}" \
        "${GRAY}        📁 目录: $ROOT${RESET}" \
        "${GRAY}        📦 输出: $DIST${RESET}" \
        "${GRAY}        🔗 主页: https://www.coolapk.com/u/31946549${RESET}" \
        "" \
        "${BLUE}${LINE}${RESET}" \
        ""
}

print_line() {
    printf '%b\n' "${BLUE}${LINE}${RESET}"
}

# ============================================================
#  杂鱼吐槽（新增）
# ============================================================
fish_say() {
    local emojis=("🐟" "🐠" "🐡" "🎣" "📱" "🔍" "📦")
    local idx=$((RANDOM % ${#emojis[@]}))
    printf '%b\n' "${CYAN}[${emojis[$idx]}]${RESET} ${1}${RESET}"
}
fish_warn() {
    local warnings=("⚠️" "🚧" "📢" "💡" "🤔")
    local idx=$((RANDOM % ${#warnings[@]}))
    printf '%b\n' "${YELLOW}[${warnings[$idx]}]${RESET} ${1}${RESET}"
}
fish_error() {
    local errors=("❌" "💥" "🚫" "😱" "💀")
    local idx=$((RANDOM % ${#errors[@]}))
    printf '%b\n' "${RED}[${errors[$idx]}]${RESET} ${1}${RESET}"
}
fish_success() {
    local successes=("✅" "🎉" "✨" "👍" "💯")
    local idx=$((RANDOM % ${#successes[@]}))
    printf '%b\n' "${GREEN}[${successes[$idx]}]${RESET} ${1}${RESET}"
}

# ============================================================
#  杂鱼确认语（新增）
# ============================================================
confirm_installation() {
    printf '%b\n' "" \
        "${ORANGE}${BOLD}🤔 杂鱼${RESET}${CYAN}真的要继续吗？确认之后就别反悔哦！🤓${RESET}" \
        "${CYAN}✨ 输入 '${GREEN}${BOLD}y${RESET}${CYAN}' 确认 ${RED}⚡ ${CYAN}输入 '${RED}${BOLD}n${RESET}${CYAN}' 取消 ${PINK}(｡>∀<｡)${RESET}"
    printf '%b' "${YELLOW}🎮 请选择 [y/n]: ${RESET}"

    local saved
    saved=$(stty -g 2>/dev/null)
    stty echo icanon 2>/dev/null

    local choice
    read -r choice

    [ -n "$saved" ] && stty "$saved" 2>/dev/null

    case "$choice" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# ============================================================
#  文件检查
# ============================================================
check_files() {
    local files="
module.prop
customize.sh
post-fs-data.sh
post-mount.sh
service.sh
uninstall.sh
bin/common.sh
bin/bootanimctl.sh
webroot/index.html
webroot/theme.css
payload/MIUI粒子效果.zip
payload/MIUI粒子动画oneplus.zip
META-INF/com/google/android/update-binary
META-INF/com/google/android/updater-script
"
    echo "$files" | while IFS= read -r f; do
        [ -z "$f" ] && continue
        [ -f "$ROOT/$f" ] || echo "$f"
    done > /tmp/.build-missing-$$

    local count
    count=$(wc -l < /tmp/.build-missing-$$ 2>/dev/null | tr -d ' ')

    if [ "$count" -gt 0 ]; then
        fish_error "缺少 $count 个文件："
        echo ""
        while IFS= read -r f; do
            echo -e "   ${RED}✗${RESET} $f"
        done < /tmp/.build-missing-$$
        rm -f /tmp/.build-missing-$$
        return 1
    fi
    rm -f /tmp/.build-missing-$$
    fish_success "所有文件齐全"
    return 0
}

# ============================================================
#  进度条（保留原样）
# ============================================================
show_progress() {
    local text="$1" pct="$2"
    local filled=$((pct / 5))
    local empty=$((20 - filled))
    local bar=""
    local i=0
    while [ "$i" -lt "$filled" ]; do bar="${bar}█"; i=$((i + 1)); done
    i=0
    while [ "$i" -lt "$empty" ]; do bar="${bar}░"; i=$((i + 1)); done
    printf '%b\n' "${CYAN}🐟 ${text} ${RESET}${GREEN}[${bar}]${RESET} ${BOLD}$(printf '%3d' "$pct")%${RESET}"
}

# ============================================================
#  键盘读取（保留原样）
# ============================================================
read_key() {
    local key=""
    IFS= read -r -n 1 key 2>/dev/null

    if [ "$key" = "$(printf '\033')" ]; then
        local seq1="" seq2=""
        IFS= read -r -n 1 -t 1 seq1 2>/dev/null
        IFS= read -r -n 1 -t 1 seq2 2>/dev/null
        if [ "$seq1" = "[" ]; then
            case "$seq2" in
                A) echo "UP" ;;
                B) echo "DOWN" ;;
                *) echo "OTHER" ;;
            esac
        else
            echo "OTHER"
        fi
    elif [ -z "$key" ]; then
        echo "ENTER"
    elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
        echo "QUIT"
    elif [ "$key" = "$(printf '\n')" ] || [ "$key" = "$(printf '\r')" ]; then
        echo "ENTER"
    else
        echo "OTHER"
    fi
}

ui_input() {
    local prompt="$1" default="$2"

    printf '%b\n' "${YELLOW}${prompt}${RESET}" >&2
    printf '%b\n' "${GRAY}   默认: ${default}${RESET}" >&2
    printf '%b' "${PINK}   > ${RESET}" >&2

    local saved
    saved=$(stty -g 2>/dev/null)
    stty echo icanon 2>/dev/null

    local ans
    read -r ans

    # 恢复进入函数前的终端状态（可能是 -echo -icanon）
    [ -n "$saved" ] && stty "$saved" 2>/dev/null

    if [ -z "$ans" ]; then
        printf '%s\n' "$default"
    else
        printf '%s\n' "$ans"
    fi
}

read_user_input() {
    local saved
    saved=$(stty -g 2>/dev/null)
    stty echo icanon 2>/dev/null
    read -r "$@"
    local ret=$?
    [ -n "$saved" ] && stty "$saved" 2>/dev/null
    return $ret
}

# ============================================================
#  箭头菜单（保留原样）
# ============================================================
MENU_INDEX=0

arrow_menu() {
    local title="$1"
    shift
    local items=("$@")
    local count=${#items[@]}
    MENU_INDEX=0

    while true; do
        show_ui
        printf '%b\n' "${GOLD}${BOLD}${title}${RESET}" ""

        local i=0
        while [ "$i" -lt "$count" ]; do
            if [ "$i" -eq "$MENU_INDEX" ]; then
                printf '%b\n' "   ${BG_SELECT}${FG_SELECT}${BOLD} ▶ ${items[$i]}  ${RESET}"
            else
                printf '%b\n' "     ${GRAY}${items[$i]}${RESET}"
            fi
            i=$((i + 1))
        done

        printf '%b\n' "" "${BLUE}${LINE}${RESET}" "" \
            "${GRAY}   ↑/↓ 移动   Enter 确认   q 退出${RESET}" ""

        local key
        key=$(read_key)
        case "$key" in
            UP)   MENU_INDEX=$((MENU_INDEX - 1)); [ "$MENU_INDEX" -lt 0 ] && MENU_INDEX=$((count - 1)) ;;
            DOWN) MENU_INDEX=$((MENU_INDEX + 1)); [ "$MENU_INDEX" -ge "$count" ] && MENU_INDEX=0 ;;
            ENTER) return 0 ;;
            QUIT)  MENU_INDEX=-1; return 1 ;;
        esac
    done
}

# ============================================================
#  打包单个变体
# ============================================================
build_one() {
    local variant="$1"
    local brand="$2"
    local keep_anim="$3"

    local tmp="$ROOT/.build-tmp-$variant"
    local out_zip="$DIST/HyperOS-Boot-Animation-Module-${variant}-${STAMP}.zip"

    rm -rf "$tmp"
    mkdir -p "$tmp"

    mkdir -p "$tmp/META-INF/com/google/android"
    cp -fp "$ROOT/META-INF/com/google/android/update-binary" "$tmp/META-INF/com/google/android/"
    cp -fp "$ROOT/META-INF/com/google/android/updater-script" "$tmp/META-INF/com/google/android/"
    chmod 0755 "$tmp/META-INF/com/google/android/update-binary"
    chmod 0644 "$tmp/META-INF/com/google/android/updater-script"

    for f in module.prop customize.sh post-fs-data.sh post-mount.sh service.sh uninstall.sh; do
        cp -fp "$ROOT/$f" "$tmp/$f"
    done

    mkdir -p "$tmp/bin" "$tmp/webroot"
    cp -fp "$ROOT/bin/common.sh" "$ROOT/bin/bootanimctl.sh" "$ROOT/bin/module-desc.sh" "$tmp/bin/"
    cp -fp "$ROOT/webroot/index.html" "$ROOT/webroot/theme.css" "$tmp/webroot/"

    mkdir -p "$tmp/payload/animations" "$tmp/payload/backups"
    local anim_name
    anim_name=$(basename "$keep_anim")
    if ! ln -f "$keep_anim" "$tmp/payload/$anim_name" 2>/dev/null; then
        cp -fp "$keep_anim" "$tmp/payload/"
    fi
    printf '%b' "$brand" > "$tmp/payload/.brand"
    touch "$tmp/payload/.keep" \
          "$tmp/payload/animations/.keep" \
          "$tmp/payload/backups/.keep" \
          "$tmp/payload/backups/index.txt"

    mkdir -p "$tmp/var/logs" "$tmp/var/state" "$tmp/var/tmp"
    touch "$tmp/var/logs/.keep" "$tmp/var/state/.keep" "$tmp/var/tmp/.keep"

    chmod 0755 "$tmp/customize.sh" "$tmp/post-fs-data.sh" "$tmp/post-mount.sh" \
               "$tmp/service.sh" "$tmp/uninstall.sh" \
               "$tmp/bin/common.sh" "$tmp/bin/bootanimctl.sh"
    chmod 0644 "$tmp/module.prop" "$tmp/webroot/index.html" "$tmp/webroot/theme.css"

    ( cd "$tmp" && zip -rq "$out_zip" . -x ".*" -x "*/.*" 2>/dev/null )
    ( cd "$tmp" && zip -q "$out_zip" \
        payload/.brand payload/.keep payload/animations/.keep \
        payload/backups/.keep payload/backups/index.txt \
        var/logs/.keep var/state/.keep var/tmp/.keep 2>/dev/null )

    rm -rf "$tmp"

    if [ -f "$out_zip" ]; then
        if ! verify_zip "$out_zip" >/dev/null 2>&1; then
            fish_warn "包验证有问题："
            verify_zip "$out_zip" >&2
        fi
        echo "$out_zip"
        return 0
    fi
    return 1
}

# ============================================================
#  验证 zip
# ============================================================
verify_zip() {
    local z="$1"
    [ -f "$z" ] || return 1

    local flist="
META-INF/com/google/android/update-binary
META-INF/com/google/android/updater-script
module.prop
customize.sh
post-fs-data.sh
post-mount.sh
service.sh
uninstall.sh
bin/common.sh
bin/bootanimctl.sh
webroot/index.html
webroot/theme.css
payload/.brand
payload/.keep
payload/animations/.keep
payload/backups/.keep
payload/backups/index.txt
var/logs/.keep
var/state/.keep
var/tmp/.keep
"
    echo "$flist" | while IFS= read -r f; do
        [ -z "$f" ] && continue
        unzip -l "$z" 2>/dev/null | grep -q " $f" || echo "$f"
    done > /tmp/.verify-missing-$$

    local count
    count=$(wc -l < /tmp/.verify-missing-$$ 2>/dev/null | tr -d ' ')

    if [ "$count" -gt 0 ]; then
        printf '%b\n' "${RED}⚠️  包缺少 $count 个文件：${RESET}"
        while IFS= read -r f; do
            printf '%b\n' "   ${RED}✗${RESET} $f"
        done < /tmp/.verify-missing-$$
        rm -f /tmp/.verify-missing-$$
        return 1
    fi
    rm -f /tmp/.verify-missing-$$
    return 0
}

# ============================================================
#  打包流程
# ============================================================
do_build() {
    local mode="$1"

    show_ui

    local out_dir
    out_dir=$(ui_input "🎯 输出目录（回车用默认，输入 N 可自定义）：" "$DIST")

    if [ "$out_dir" = "N" ] || [ "$out_dir" = "n" ]; then
        out_dir=$(ui_input "📁 请输入自定义输出路径：" "$DIST")
    fi

    if [ -e "$out_dir" ]; then
        if [ ! -d "$out_dir" ]; then
            fish_error "路径已存在但不是目录：$out_dir"
            printf '%b' "${GRAY}按回车键继续...${RESET}"; read_user_input _
            return 1
        fi
        if [ ! -w "$out_dir" ]; then
            fish_error "目录不可写：$out_dir"
            printf '%b' "${GRAY}按回车键继续...${RESET}"; read_user_input _
            return 1
        fi
    else
        if ! mkdir -p "$out_dir" 2>/dev/null; then
            fish_error "无法创建目录：$out_dir"
            printf '%b' "${GRAY}按回车键继续...${RESET}"; read_user_input _
            return 1
        fi
    fi

    local do_h=0 do_o=0
    case "$mode" in
        all)     do_h=1; do_o=1 ;;
        hyperos) do_h=1 ;;
        oneplus) do_o=1 ;;
    esac

    printf '%b\n' "${PINK}🐟 准备打包${RESET}" ""
    if [ "$do_h" = "1" ]; then
        local h_size
        h_size=$(du -h "$ROOT/payload/MIUI粒子效果.zip" 2>/dev/null | cut -f1)
        printf '%b\n' \
            "${GREEN}   📦 HyperOS 变体${RESET}" \
            "${GRAY}      ├─ 品牌: xiaomi${RESET}" \
            "${GRAY}      └─ 动画: MIUI粒子效果.zip (${h_size})${RESET}" ""
    fi
    if [ "$do_o" = "1" ]; then
        local o_size
        o_size=$(du -h "$ROOT/payload/MIUI粒子动画oneplus.zip" 2>/dev/null | cut -f1)
        printf '%b\n' \
            "${GREEN}   📦 一加变体${RESET}" \
            "${GRAY}      ├─ 品牌: oneplus${RESET}" \
            "${GRAY}      └─ 动画: MIUI粒子动画oneplus.zip (${o_size})${RESET}" ""
    fi
    printf '%b\n' "${GRAY}   输出目录: $out_dir${RESET}" ""

    if ! confirm_installation; then
        fish_warn "取消打包"
        return 0
    fi

    printf '\n'
    print_line
    printf '\n'

    check_files || { printf '%b' "${GRAY}按回车键继续...${RESET}"; read_user_input _; return 1; }

    printf '\n'

    local hyper_out="" oneplus_out=""
    local hyper_ok=1 oneplus_ok=1

    if [ "$do_h" = "1" ]; then
        show_progress "正在打包 HyperOS 变体..." 0
        hyper_out=$(build_one "hyperos" "xiaomi" "$ROOT/payload/MIUI粒子效果.zip")
        hyper_ok=$?
        show_progress "正在打包 HyperOS 变体..." 100
        printf '\n'
    fi

    if [ "$do_o" = "1" ]; then
        show_progress "正在打包 一加变体..." 0
        oneplus_out=$(build_one "oneplus" "oneplus" "$ROOT/payload/MIUI粒子动画oneplus.zip")
        oneplus_ok=$?
        show_progress "正在打包 一加变体..." 100
        printf '\n'
    fi

    print_line
    printf '\n'
    fish_success "打包完成！"
    printf '\n'

    if [ "$do_h" = "1" ]; then
        if [ "$hyper_ok" -eq 0 ] && [ -f "$hyper_out" ]; then
            printf '%b\n' \
                "${GREEN}   ✅ HyperOS 变体${RESET}" \
                "${GRAY}      文件: $(basename "$hyper_out")${RESET}" \
                "${GRAY}      大小: $(du -h "$hyper_out" | cut -f1)${RESET}" ""
        else
            fish_error "HyperOS 变体打包失败"
            printf '\n'
        fi
    fi

    if [ "$do_o" = "1" ]; then
        if [ "$oneplus_ok" -eq 0 ] && [ -f "$oneplus_out" ]; then
            printf '%b\n' \
                "${GREEN}   ✅ 一加变体${RESET}" \
                "${GRAY}      文件: $(basename "$oneplus_out")${RESET}" \
                "${GRAY}      大小: $(du -h "$oneplus_out" | cut -f1)${RESET}" ""
        else
            fish_error "一加变体打包失败"
            printf '\n'
        fi
    fi

    printf '%b\n' \
        "${CYAN}   📁 输出: $out_dir${RESET}" "" \
        "${YELLOW}   💡 把 zip 传到手机，用 Magisk/KernelSU/APatch 刷入${RESET}" ""

    printf '%b' "${PINK}按回车键继续...${RESET}"
    read_user_input _
}

# ============================================================
#  清理
# ============================================================
do_clean() {
    show_ui
    printf '%b\n' \
        "${YELLOW}⚠️  将删除：${RESET}" \
        "${GRAY}   $DIST${RESET}" \
        "${GRAY}   $ROOT/.build-tmp*${RESET}" ""

    if confirm_installation; then
        rm -rf "$DIST" "$ROOT"/.build-tmp*
        fish_success "已清理"
    else
        fish_warn "取消"
    fi
    printf '\n'
    printf '%b' "${PINK}按回车键继续...${RESET}"
    read_user_input _
}

# ============================================================
#  查看已有包
# ============================================================
do_list() {
    show_ui

    if [ ! -d "$DIST" ]; then
        fish_warn "dist/ 目录不存在"
    else
        local files
        files=$(ls -1 "$DIST"/*.zip 2>/dev/null)
        if [ -z "$files" ]; then
            fish_warn "dist/ 为空"
        else
            fish_say "已有包："
            printf '\n'
            for f in $files; do
                printf '%b\n' \
                    "${GREEN}   📦 $(basename "$f")${RESET}" \
                    "${GRAY}      $(du -h "$f" | cut -f1)${RESET}"
            done
        fi
    fi
    printf '\n'
    printf '%b' "${PINK}按回车键继续...${RESET}"
    read_user_input _
}

# ============================================================
#  检查文件
# ============================================================
do_check() {
    show_ui
    fish_say "检查文件完整性..."
    printf '\n'
    if check_files; then
        printf '%b\n' "" "${YELLOW}📊 源码目录：${RESET}" "" \
            "${GRAY}   bin/      $(ls -1 "$ROOT/bin" 2>/dev/null | wc -l) 个文件${RESET}" \
            "${GRAY}   webroot/  $(ls -1 "$ROOT/webroot" 2>/dev/null | wc -l) 个文件${RESET}" \
            "${GRAY}   payload/  $(ls -1 "$ROOT/payload"/*.zip 2>/dev/null | wc -l) 个动画${RESET}" \
            "${GRAY}   总大小    $(du -sh "$ROOT" 2>/dev/null | cut -f1)${RESET}"
    fi
    printf '\n'
    printf '%b' "${PINK}按回车键继续...${RESET}"
    read_user_input _
}

# ============================================================
#  主菜单（圆框 + 方向键）
# ============================================================
_STTY_SAVED=$(stty -g 2>/dev/null)
stty -echo -icanon min 1 time 0 2>/dev/null

while true; do
    arrow_menu "✨ 请选择操作 (◕‿◕✿)" \
        "🚀 打包全部（HyperOS + 一加）" \
        "🎯 只打 HyperOS 变体" \
        "🎯 只打 一加 变体" \
        "🧹 清理 dist/ 和临时文件" \
        "📋 查看已有包" \
        "🔍 检查文件完整性" \
        "🚪 退出"

    case "$MENU_INDEX" in
        0) do_build "all" ;;
        1) do_build "hyperos" ;;
        2) do_build "oneplus" ;;
        3) do_clean ;;
        4) do_list ;;
        5) do_check ;;
        6|-1)
            stty "$_STTY_SAVED" 2>/dev/null
            printf '%b\n' "${PINK}🐟 再见啦～ (´｡• ω •｡\`) ♡${RESET}"
            exit 0
            ;;
    esac
done

stty "$_STTY_SAVED" 2>/dev/null