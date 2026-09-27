#!/system/bin/sh
# ============================================================
#  小杂鱼的模块推送工具 v1.7
#  风格：圆框标题 + 方向键选择 + 杂鱼工具箱吐槽味
#  用法：su -c "sh push.sh"
#  作用：把源码目录里改过的文件，覆盖到已装模块目录（边改边测）
# ============================================================

if [ -z "$BASH_VERSION" ]; then
    command -v bash >/dev/null 2>&1 && exec bash "$0" "$@"
    [ -x /system/bin/bash ] && exec /system/bin/bash "$0" "$@"
    echo "❌ 需要 bash，请先 pkg install bash"
    exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
MODULE_ID="hyperosbootanim"
TARGET="/data/adb/modules/$MODULE_ID"

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

BG_CHECK='\033[48;5;46m'
FG_CHECK='\033[30m'

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}❌ 需要 root 权限${RESET}"
    echo -e "${YELLOW}💡 请用：${RESET}"
    echo -e "${CYAN}   su -c \"sh push.sh\"${RESET}"
    exit 1
fi

# ============================================================
#  圆框标题（保留原样）
# ============================================================
LINE="〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓"

show_ui() {
    clear
    echo -e "${PINK}"
    echo "    ╭───────────────────────────────────────╮"
    echo "    │      🐟 小杂鱼的模块推送工具 🐟       │"
    echo "    │              push v1.7                │"
    echo "    ╰───────────────────────────────────────╯"
    echo -e "${RESET}"
    echo -e "${GRAY}        📁 源码: $ROOT${RESET}"
    echo -e "${GRAY}        🎯 目标: $TARGET${RESET}"
    echo -e "${GRAY}        🎨 风格: 幸せな小さな雑魚${RESET}"
    echo -e "${GRAY}        🔗 主页: https://www.coolapk.com/u/31946549${RESET}"
    echo ""
    echo -e "${BLUE}${LINE}${RESET}"
    echo ""
}

print_line() {
    echo -e "${BLUE}${LINE}${RESET}"
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
#  键盘读取（保留原样）
# ============================================================
read_key() {
    local stty_saved=$(stty -g 2>/dev/null)
    stty -echo -icanon min 1 time 0 2>/dev/null

    local key=""
    IFS= read -r -n 1 key 2>/dev/null

    if [ "$key" = "$(printf '\033')" ]; then
        local seq1="" seq2=""
        IFS= read -r -n 1 -t 1 seq1 2>/dev/null
        IFS= read -r -n 1 -t 1 seq2 2>/dev/null
        if [ "$seq1" = "[" ]; then
            case "$seq2" in
                A) key="UP" ;;
                B) key="DOWN" ;;
                C) key="RIGHT" ;;
                D) key="LEFT" ;;
                *) key="OTHER" ;;
            esac
        else
            key="OTHER"
        fi
    elif [ -z "$key" ]; then
        key="ENTER"
    elif [ "$key" = " " ]; then
        key="SPACE"
    elif [ "$key" = "a" ] || [ "$key" = "A" ]; then
        key="ALL"
    elif [ "$key" = "n" ] || [ "$key" = "N" ]; then
        key="NONE"
    elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
        key="QUIT"
    elif [ "$key" = "$(printf '\n')" ] || [ "$key" = "$(printf '\r')" ]; then
        key="ENTER"
    else
        key="OTHER"
    fi

    stty "$stty_saved" 2>/dev/null
    echo "$key"
}

# ============================================================
#  单选菜单（保留原样）
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
        echo -e "${GOLD}${BOLD}${title}${RESET}"
        echo ""

        local i=0
        while [ "$i" -lt "$count" ]; do
            if [ "$i" -eq "$MENU_INDEX" ]; then
                echo -e "   ${BG_SELECT}${BOLD_SELECT}${FG_SELECT} ▶ ${items[$i]}  ${RESET}"
            else
                echo -e "     ${GRAY}${items[$i]}${RESET}"
            fi
            i=$((i + 1))
        done

        echo ""
        print_line
        echo ""
        echo -e "${GRAY}   ↑/↓ 移动   Enter 确认   q 退出${RESET}"
        echo ""

        local key=$(read_key)
        case "$key" in
            UP)
                MENU_INDEX=$((MENU_INDEX - 1))
                [ "$MENU_INDEX" -lt 0 ] && MENU_INDEX=$((count - 1))
                ;;
            DOWN)
                MENU_INDEX=$((MENU_INDEX + 1))
                [ "$MENU_INDEX" -ge "$count" ] && MENU_INDEX=0
                ;;
            ENTER)
                return 0
                ;;
            QUIT)
                MENU_INDEX=-1
                return 1
                ;;
        esac
    done
}

# ============================================================
#  多选菜单（保留原样）
# ============================================================
CHECKED=()
CHECK_COUNT=0

checklist_menu() {
    local title="$1"
    shift
    local items=("$@")
    local count=${#items[@]}

    CHECKED=()
    local i=0
    while [ "$i" -lt "$count" ]; do
        CHECKED+=("0")
        i=$((i + 1))
    done
    CHECK_COUNT=0

    local idx=0

    while true; do
        show_ui

        echo -e "${GOLD}${BOLD}${title}${RESET}"
        echo ""

        i=0
        while [ "$i" -lt "$count" ]; do
            local mark="[ ]"
            [ "${CHECKED[$i]}" = "1" ] && mark="[✓]"

            if [ "$i" -eq "$idx" ]; then
                echo -e "   ${BG_SELECT}${BOLD_SELECT}${FG_SELECT} ▶ ${mark} ${items[$i]}  ${RESET}"
            elif [ "${CHECKED[$i]}" = "1" ]; then
                echo -e "     ${GREEN}${mark}${RESET} ${items[$i]}"
            else
                echo -e "     ${GRAY}${mark}${RESET} ${DIM}${items[$i]}${RESET}"
            fi
            i=$((i + 1))
        done

        echo ""
        print_line
        echo ""
        echo -e "${GRAY}   ↑/↓ 移动   Space 切换   a 全选   n 全不选${RESET}"
        echo -e "${GRAY}   Enter 确认   q 取消${RESET}"
        echo ""
        echo -e "${CYAN}   已选: $CHECK_COUNT / $count${RESET}"
        echo ""

        local key=$(read_key)
        case "$key" in
            UP)
                idx=$((idx - 1))
                [ "$idx" -lt 0 ] && idx=$((count - 1))
                ;;
            DOWN)
                idx=$((idx + 1))
                [ "$idx" -ge "$count" ] && idx=0
                ;;
            SPACE)
                if [ "${CHECKED[$idx]}" = "1" ]; then
                    CHECKED[$idx]="0"
                    CHECK_COUNT=$((CHECK_COUNT - 1))
                else
                    CHECKED[$idx]="1"
                    CHECK_COUNT=$((CHECK_COUNT + 1))
                fi
                ;;
            ALL)
                i=0
                while [ "$i" -lt "$count" ]; do
                    CHECKED[$i]="1"
                    i=$((i + 1))
                done
                CHECK_COUNT=$count
                ;;
            NONE)
                i=0
                while [ "$i" -lt "$count" ]; do
                    CHECKED[$i]="0"
                    i=$((i + 1))
                done
                CHECK_COUNT=0
                ;;
            ENTER)
                return 0
                ;;
            QUIT)
                return 1
                ;;
        esac
    done
}

# ============================================================
#  检查目标模块
# ============================================================
check_target() {
    if [ ! -d "$TARGET" ]; then
        fish_error "找不到已装模块："
        echo -e "${GRAY}   $TARGET${RESET}"
        echo ""
        fish_warn "可能原因："
        echo -e "${CYAN}   • 模块还没装${RESET}"
        echo -e "${CYAN}   • 模块 id 不是 $MODULE_ID${RESET}"
        echo ""
        fish_say "/data/adb/modules/ 里现有的模块："
        if [ -d "/data/adb/modules" ]; then
            ls -1 "/data/adb/modules" 2>/dev/null | while read m; do
                echo -e "${GRAY}   • $m${RESET}"
            done
        else
            echo -e "${GRAY}   （目录不存在）${RESET}"
        fi
        return 1
    fi

    if [ ! -f "$TARGET/module.prop" ]; then
        fish_warn "目标目录存在，但 module.prop 缺失"
        return 1
    fi

    fish_success "找到已装模块："
    local name=$(grep '^name=' "$TARGET/module.prop" 2>/dev/null | cut -d= -f2)
    local version=$(grep '^version=' "$TARGET/module.prop" 2>/dev/null | cut -d= -f2)
    echo -e "${GRAY}   $name $version${RESET}"
    return 0
}

# ============================================================
#  候选文件列表
# ============================================================
ALL_FILES=""
ALL_LABELS=()

scan_all_files() {
    ALL_FILES=""
    ALL_LABELS=()

    for f in module.prop uninstall.sh \
             post-fs-data.sh post-mount.sh service.sh \
             bin/common.sh bin/bootanimctl.sh bin/module-desc.sh \
             webroot/index.html webroot/theme.css \
             payload/.brand; do
        if [ -f "$ROOT/$f" ]; then
            ALL_FILES="$ALL_FILES $f"
            local status=""
            if [ -f "$TARGET/$f" ]; then
                if cmp -s "$ROOT/$f" "$TARGET/$f" 2>/dev/null; then
                    status="(相同)"
                else
                    status="(有变化)"
                fi
            else
                status="(新增)"
            fi
            ALL_LABELS+=("$f $status")
        fi
    done
}

# ============================================================
#  执行推送
# ============================================================
do_push() {
    show_ui

    fish_say "检查目标模块..."
    echo ""
    check_target || { echo ""; printf '%b' "${PINK}按回车键继续...${RESET}"; read -r; return 1; }
    echo ""

    scan_all_files

    if [ -z "$ALL_FILES" ]; then
        fish_error "源码目录里没有可推的文件"
        printf '%b' "${PINK}按回车键继续...${RESET}"
        read -r
        return 1
    fi

    if ! checklist_menu "📋 选择要推送的文件：" "${ALL_LABELS[@]}"; then
        fish_warn "取消"
        sleep 1
        return 0
    fi

    if [ "$CHECK_COUNT" -eq 0 ]; then
        echo ""
        fish_warn "没有选中任何文件"
        printf '%b' "${PINK}按回车键继续...${RESET}"
        read -r
        return 0
    fi

    local SELECTED_FILES=""
    local i=0
    for f in $ALL_FILES; do
        if [ "${CHECKED[$i]}" = "1" ]; then
            SELECTED_FILES="$SELECTED_FILES $f"
        fi
        i=$((i + 1))
    done

    show_ui
    fish_say "将要推送 $CHECK_COUNT 个文件："
    echo ""
    for f in $SELECTED_FILES; do
        local src_size=$(du -h "$ROOT/$f" 2>/dev/null | cut -f1)
        echo -e "${GREEN}   ✓ $f ($src_size)${RESET}"
    done
    echo ""
    print_line
    echo ""

    if ! confirm_installation; then
        fish_warn "取消推送"
        sleep 1
        return 0
    fi

    echo ""
    fish_say "开始推送..."
    echo ""

    local ok=0
    local fail=0

    for f in $SELECTED_FILES; do
        local dst_dir=$(dirname "$TARGET/$f")
        mkdir -p "$dst_dir" 2>/dev/null

        if cp -fp "$ROOT/$f" "$TARGET/$f" 2>/dev/null; then
            case "$f" in
                *.sh) chmod 0755 "$TARGET/$f" 2>/dev/null ;;
                *)    chmod 0644 "$TARGET/$f" 2>/dev/null ;;
            esac
            chown 0:0 "$TARGET/$f" 2>/dev/null
            ok=$((ok + 1))
            echo -e "   ${GREEN}✅${RESET} $f"
        else
            fail=$((fail + 1))
            echo -e "   ${RED}❌${RESET} $f"
        fi
    done

    echo ""
    print_line
    echo ""
    fish_success "推送完成！"
    echo ""
    echo -e "${GRAY}   成功: $ok 个${RESET}"
    [ "$fail" -gt 0 ] && echo -e "${RED}   失败: $fail 个${RESET}"
    echo ""
    printf '%b' "${PINK}按回车键继续...${RESET}"
    read -r
}

# ============================================================
#  仅推送有变化的文件
# ============================================================
push_changed() {
    show_ui

    fish_say "检查目标模块..."
    echo ""
    check_target || { echo ""; printf '%b' "${PINK}按回车键继续...${RESET}"; read -r; return 1; }
    echo ""

    scan_all_files

    if [ -z "$ALL_FILES" ]; then
        fish_error "源码目录里没有可推的文件"
        printf '%b' "${PINK}按回车键继续...${RESET}"
        read -r
        return 1
    fi

    local CHANGED_FILES=""
    local CHANGED_COUNT=0
    for f in $ALL_FILES; do
        local status=""
        if [ -f "$TARGET/$f" ]; then
            if cmp -s "$ROOT/$f" "$TARGET/$f" 2>/dev/null; then
                status="same"
            else
                status="diff"
            fi
        else
            status="new"
        fi

        if [ "$status" != "same" ]; then
            CHANGED_FILES="$CHANGED_FILES $f"
            CHANGED_COUNT=$((CHANGED_COUNT + 1))
        fi
    done

    show_ui
    if [ "$CHANGED_COUNT" -eq 0 ]; then
        fish_success "所有文件都是最新的，无需推送"
        echo ""
        printf '%b' "${PINK}按回车键继续...${RESET}"
        read -r
        return 0
    fi

    fish_say "检测到 $CHANGED_COUNT 个文件有变化："
    echo ""
    for f in $CHANGED_FILES; do
        local src_size=$(du -h "$ROOT/$f" 2>/dev/null | cut -f1)
        local tag=""
        if [ -f "$TARGET/$f" ]; then
            tag="${YELLOW}(有变化)${RESET}"
        else
            tag="${GREEN}(新增)${RESET}"
        fi
        echo -e "   ${GREEN}✓${RESET} $f ($src_size) $tag"
    done
    echo ""
    print_line
    echo ""

    if ! confirm_installation; then
        fish_warn "取消推送"
        sleep 1
        return 0
    fi

    echo ""
    fish_say "开始推送..."
    echo ""

    local ok=0
    local fail=0

    for f in $CHANGED_FILES; do
        local dst_dir=$(dirname "$TARGET/$f")
        mkdir -p "$dst_dir" 2>/dev/null

        if cp -fp "$ROOT/$f" "$TARGET/$f" 2>/dev/null; then
            case "$f" in
                *.sh) chmod 0755 "$TARGET/$f" 2>/dev/null ;;
                *)    chmod 0644 "$TARGET/$f" 2>/dev/null ;;
            esac
            chown 0:0 "$TARGET/$f" 2>/dev/null
            ok=$((ok + 1))
            echo -e "   ${GREEN}✅${RESET} $f"
        else
            fail=$((fail + 1))
            echo -e "   ${RED}❌${RESET} $f"
        fi
    done

    echo ""
    print_line
    echo ""
    fish_success "推送完成！"
    echo ""
    echo -e "${GRAY}   成功: $ok 个${RESET}"
    [ "$fail" -gt 0 ] && echo -e "${RED}   失败: $fail 个${RESET}"
    echo ""
    printf '%b' "${PINK}按回车键继续...${RESET}"
    read -r
}

# ============================================================
#  对比文件
# ============================================================
do_diff() {
    show_ui

    fish_say "对比源码与已装模块..."
    echo ""
    check_target || { echo ""; printf '%b' "${PINK}按回车键继续...${RESET}"; read -r; return 1; }
    echo ""

    scan_all_files

    if [ -z "$ALL_FILES" ]; then
        fish_error "源码目录里没有可对比的文件"
        printf '%b' "${PINK}按回车键继续...${RESET}"
        read -r
        return 1
    fi

    echo ""
    fish_say "对比结果："
    echo ""

    local same=0
    local diff=0
    local new=0

    for f in $ALL_FILES; do
        if [ ! -f "$TARGET/$f" ]; then
            echo -e "${GREEN}   + $f ${BOLD}(新增)${RESET}"
            new=$((new + 1))
        elif cmp -s "$ROOT/$f" "$TARGET/$f" 2>/dev/null; then
            echo -e "${GRAY}   ○ $f ${DIM}(相同)${RESET}"
            same=$((same + 1))
        else
            echo -e "${YELLOW}   ● $f ${GREEN}(有变化)${RESET}"
            diff=$((diff + 1))
        fi
    done

    echo ""
    print_line
    echo ""
    echo -e "${GRAY}   相同: $same 个${RESET}"
    echo -e "${YELLOW}   有变化: $diff 个${RESET}"
    echo -e "${GREEN}   新增: $new 个${RESET}"
    echo ""
    printf '%b' "${PINK}按回车键继续...${RESET}"
    read -r
}

# ============================================================
#  主菜单（圆框 + 方向键）
# ============================================================
while true; do
    arrow_menu "✨ 请选择操作 (◕‿◕✿)" \
        "🚀 推送修改到已装模块" \
        "📤 仅推送有变化的文件" \
        "🔍 对比源码与模块差异" \
        "🚪 退出"

    case "$MENU_INDEX" in
        0) do_push ;;
        1) push_changed ;;
        2) do_diff ;;
        3|-1)
            echo -e "${PINK}🐟 再见啦～ (´｡• ω •｡\`) ♡${RESET}"
            exit 0
            ;;
    esac
done