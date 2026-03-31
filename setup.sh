#!/bin/bash
# XClaw 交互式一键配置脚本
# 自动完成 1-6 部分配置：安装 → 插件 → 子智能体 → 技能 → API Key → 重启 Gateway
# 支持断点续传：中断后可从断点继续执行

# 不使用 set -e（会导致 confirm_continue 的 skip 触发退出）
# 用 trap 捕获中断信号，保存断点状态
set -o pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 断点续传：状态文件
STATE_FILE="$SCRIPT_DIR/.setup_state"

# 保存已完成的步骤
mark_step_done() {
    local step=$1
    if ! grep -qx "$step" "$STATE_FILE" 2>/dev/null; then
        echo "$step" >> "$STATE_FILE"
    fi
}

# 检查步骤是否已完成
is_step_done() {
    local step=$1
    grep -qx "$step" "$STATE_FILE" 2>/dev/null
}

# 显示已完成的步骤
show_progress() {
    echo ""
    echo -e "${CYAN}📋 步骤进度：${NC}"
    for i in 0 1 2 3 4 5 6; do
        local label=""
        case $i in
            0) label="环境检查" ;;
            1) label="安装 OpenClaw" ;;
            2) label="安装飞书插件" ;;
            3) label="配置子智能体" ;;
            4) label="安装技能" ;;
            5) label="配置 API Key" ;;
            6) label="重启 Gateway" ;;
        esac
        if is_step_done "$i"; then
            echo -e "  ${GREEN}✓${NC} 步骤 $i: $label"
        else
            echo -e "  ${YELLOW}○${NC} 步骤 $i: $label"
        fi
    done
    echo ""
}

# 信号处理：中断时保存断点状态
cleanup() {
    echo ""
    echo ""
    echo -e "${YELLOW}⚠️  脚本被中断${NC}"
    if [ -f "$STATE_FILE" ]; then
        show_progress
        echo -e "${CYAN}💡 下次运行时可选择断点续传${NC}"
    fi
    exit 130
}
trap cleanup SIGINT SIGTERM

# 跨平台 sed 原地编辑（macOS 用 sed -i ''，Linux 用 sed -i）
sedi() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# API Keys（将在交互中收集）
MATON_API_KEY=""
TAVILY_API_KEY=""
GITHUB_TOKEN=""
GITHUB_USERNAME=""

# 统计
SKILLS_INSTALLED=0
SKILLS_FAILED=0

echo -e "${CYAN}"
cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║              🦞 XClaw 交互式一键配置脚本                     ║
║                                                              ║
║   自动完成：OpenClaw 安装 → 子智能体配置 → 技能安装        ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 函数：打印分隔线
print_line() {
    echo -e "${BLUE}────────────────────────────────────────${NC}"
}

# 函数：打印步骤标题
step_title() {
    echo ""
    print_line
    echo -e "${BLUE}[步骤 $1/6]${NC} ${YELLOW}$2${NC}"
    print_line
    echo ""
}

# 函数：确认继续
confirm_continue() {
    echo ""
    read -p "按 Enter 继续，或输入 'skip' 跳过此步骤: " choice
    if [[ "$choice" == "skip" ]]; then
        return 1
    fi
    return 0
}

# 函数：安装单个技能
install_skill() {
    local skill=$1
    local cmd=${2:-"clawhub"}
    
    echo -n "  安装 $skill ... "
    if $cmd install "$skill" --force >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        ((SKILLS_INSTALLED++))
        return 0
    else
        echo -e "${YELLOW}⚠ 失败${NC}"
        ((SKILLS_FAILED++))
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# 检测和卸载已有 OpenClaw
# ═══════════════════════════════════════════════════════════════
check_and_uninstall_openclaw() {
    echo ""
    echo -e "${CYAN}🔍 检测现有 OpenClaw 安装${NC}"
    echo ""
    
    local OPENCLAW_EXISTS=false
    local OPENCLAW_VERSION=""
    local CONFIG_EXISTS=false
    local CONFIG_SIZE=""
    
    # 检测 openclaw 命令
    if command -v openclaw &> /dev/null; then
        OPENCLAW_EXISTS=true
        OPENCLAW_VERSION=$(openclaw --version 2>&1 | head -1 || echo "未知版本")
    fi
    
    # 检测配置文件
    if [ -d "$HOME/.openclaw" ]; then
        CONFIG_EXISTS=true
        CONFIG_SIZE=$(du -sh "$HOME/.openclaw" 2>/dev/null | cut -f1 || echo "未知")
    fi
    
    # 如果都不存在，直接返回
    if [ "$OPENCLAW_EXISTS" = false ] && [ "$CONFIG_EXISTS" = false ]; then
        echo -e "${GREEN}✓${NC} 未检测到现有 OpenClaw 安装，可以全新安装"
        return 0
    fi
    
    # 显示警告信息
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                    ⚠️  检测到现有安装                        ║${NC}"
    echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
    
    if [ "$OPENCLAW_EXISTS" = true ]; then
        echo -e "${RED}║  OpenClaw 已安装: $OPENCLAW_VERSION${NC}"
    fi
    
    if [ "$CONFIG_EXISTS" = true ]; then
        echo -e "${RED}║  配置目录: ~/.openclaw (${CONFIG_SIZE})${NC}"
        echo -e "${RED}║  包含: 插件、技能、工作区、API密钥等配置${NC}"
    fi
    
    echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║  ⚠️  继续安装将覆盖/删除现有配置！                          ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # 询问用户选择
    echo "请选择操作："
    echo ""
    echo -e "  ${YELLOW}1${NC}) ${GREEN}备份现有配置${NC}，然后卸载并全新安装（推荐）"
    echo -e "  ${YELLOW}2${NC}) ${RED}直接卸载${NC}，不备份（⚠️ 数据将永久丢失）"
    echo -e "  ${YELLOW}3${NC}) ${CYAN}保留现有安装${NC}，仅更新配置和技能"
    echo -e "  ${YELLOW}4${NC}) ${BLUE}退出脚本${NC}，手动处理"
    echo ""
    read -p "请输入选项 [1-4]: " choice
    
    case $choice in
        1)
            backup_and_uninstall
            ;;
        2)
            direct_uninstall
            ;;
        3)
            echo ""
            echo -e "${YELLOW}⚠ 将保留现有 OpenClaw 安装，仅更新配置和技能${NC}"
            read -p "按 Enter 继续..."
            return 0
            ;;
        4)
            echo ""
            echo -e "${CYAN}已退出。您可以：${NC}"
            echo "  1. 手动备份: cp -r ~/.openclaw ~/.openclaw.backup"
            echo "  2. 手动卸载: ./uninstall_claw.sh"
            echo "  3. 迁移指南: https://docs.openclaw.ai/zh-CN/install/migrating"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，退出脚本${NC}"
            exit 1
            ;;
    esac
}

# 备份并卸载
backup_and_uninstall() {
    echo ""
    echo -e "${BLUE}📦 备份现有配置...${NC}"
    
    # 创建备份目录
    BACKUP_DIR="$HOME/.openclaw.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [ -d "$HOME/.openclaw" ]; then
        echo "  复制 ~/.openclaw 到备份目录..."
        cp -r "$HOME/.openclaw" "$BACKUP_DIR"
        
        # 自动验证备份
        if [ -d "$BACKUP_DIR" ] && [ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
            BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
            echo -e "${GREEN}✓${NC} 配置已备份到: ${CYAN}$BACKUP_DIR${NC} (${BACKUP_SIZE})"
        else
            echo -e "${RED}✗${NC} 备份失败！中断卸载以保护数据"
            exit 1
        fi
    fi
    
    # 执行卸载
    echo ""
    echo -e "${BLUE}🗑️  执行卸载...${NC}"
    
    # 使用项目中的卸载脚本
    if [ -f "$SCRIPT_DIR/1. 卸载旧版本和安装指定版本XClaw/uninstall_claw.sh" ]; then
        bash "$SCRIPT_DIR/1. 卸载旧版本和安装指定版本XClaw/uninstall_claw.sh"
    else
        # 内置卸载逻辑（简化版）
        builtin_uninstall
    fi
    
    # 自动验证卸载
    echo ""
    echo -e "${BLUE}🔍 验证卸载结果...${NC}"
    VERIFY_OK=true
    if command -v openclaw &> /dev/null; then
        echo -e "  ${RED}✗${NC} openclaw 命令仍存在"
        VERIFY_OK=false
    else
        echo -e "  ${GREEN}✓${NC} openclaw 命令已移除"
    fi
    if [ ! -d "$HOME/.openclaw" ] || [ -z "$(ls -A "$HOME/.openclaw" 2>/dev/null)" ]; then
        echo -e "  ${GREEN}✓${NC} 配置目录已清理"
    else
        echo -e "  ${YELLOW}⚠${NC} 配置目录仍存在（已保留）"
    fi
    if $VERIFY_OK; then
        echo -e "${GREEN}✓${NC} 卸载验证通过"
    fi
    
    echo -e "${CYAN}备份位置: $BACKUP_DIR${NC}"
    echo ""
    read -p "按 Enter 继续安装..."
}

# 直接卸载（不备份）
direct_uninstall() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║              ⚠️  警告：此操作不可恢复！                      ║${NC}"
    echo -e "${RED}║                                                              ║${NC}"
    echo -e "${RED}║  所有配置、插件、技能、工作区将被永久删除！                  ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "请输入 'DELETE' 确认继续: " confirm
    
    if [ "$confirm" != "DELETE" ]; then
        echo -e "${YELLOW}操作已取消${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${BLUE}🗑️  执行卸载...${NC}"
    
    # 使用项目中的卸载脚本
    if [ -f "$SCRIPT_DIR/1. 卸载旧版本和安装指定版本XClaw/uninstall_claw.sh" ]; then
        bash "$SCRIPT_DIR/1. 卸载旧版本和安装指定版本XClaw/uninstall_claw.sh"
    else
        builtin_uninstall
    fi
    
    # 自动验证卸载
    echo ""
    echo -e "${BLUE}🔍 验证卸载结果...${NC}"
    if command -v openclaw &> /dev/null; then
        echo -e "  ${RED}✗${NC} openclaw 命令仍存在，尝试强制清理..."
        builtin_uninstall
    else
        echo -e "  ${GREEN}✓${NC} openclaw 命令已移除"
    fi
    echo -e "${GREEN}✓${NC} 卸载验证完成"
    echo ""
    read -p "按 Enter 继续安装..."
}

# 内置卸载逻辑（当找不到卸载脚本时使用）
builtin_uninstall() {
    # 停止 Gateway
    if command -v openclaw &> /dev/null; then
        openclaw gateway stop 2>/dev/null || true
        sleep 1
    fi
    
    # 杀死残留进程
    killall -q openclaw-gateway 2>/dev/null || true
    pkill -f "openclaw" 2>/dev/null || true
    sleep 1
    
    # 卸载 npm 包
    npm uninstall -g openclaw 2>/dev/null || true
    
    # 删除二进制文件
    rm -f "$(which openclaw 2>/dev/null)" 2>/dev/null || true
    rm -f /usr/local/bin/openclaw 2>/dev/null || true
    rm -f /opt/homebrew/bin/openclaw 2>/dev/null || true
    
    # 验证 npm 卸载
    if npm list -g openclaw 2>/dev/null | grep -q "openclaw"; then
        echo -e "  ${YELLOW}⚠${NC} npm 全局包仍在，强制清理..."
        rm -rf "$(npm root -g)/openclaw" 2>/dev/null || true
    fi
    
    # 删除配置（在 backup_and_uninstall 中已备份，直接删除）
    if [ -d "$HOME/.openclaw" ] && [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
        rm -rf "$HOME/.openclaw"
        echo -e "  ${GREEN}✓${NC} 配置已删除（备份已保存）"
    elif [ -d "$HOME/.openclaw" ]; then
        echo ""
        read -p "删除配置目录 ~/.openclaw? [y/N]: " del_config
        if [[ "$del_config" =~ ^[Yy]$ ]]; then
            rm -rf "$HOME/.openclaw"
            echo -e "  ${GREEN}✓${NC} 配置已删除"
        else
            echo -e "  ${YELLOW}保留配置目录${NC}"
        fi
    fi
    
    # 清理缓存
    rm -rf "$HOME/.npm/_npx" 2>/dev/null || true
    rm -rf /tmp/openclaw* 2>/dev/null || true
}

# 执行检测和卸载
check_and_uninstall_openclaw

# ═══════════════════════════════════════════════════════════════
# 断点续传检测
# ═══════════════════════════════════════════════════════════════
if [ -f "$STATE_FILE" ]; then
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║              🔄 检测到上次未完成的配置                        ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    show_progress
    echo "请选择："
    echo -e "  ${GREEN}1${NC}) ${GREEN}断点续传${NC} — 跳过已完成的步骤，从断点继续（推荐）"
    echo -e "  ${YELLOW}2${NC}) ${YELLOW}全部重来${NC} — 清除进度，从头开始"
    echo -e "  ${BLUE}3${NC}) ${BLUE}仅执行指定步骤${NC}"
    echo ""
    read -p "请输入选项 [1-3，默认1]: " resume_choice

    case $resume_choice in
        2)
            echo ""
            echo -e "${YELLOW}清除进度记录，从头开始...${NC}"
            rm -f "$STATE_FILE"
            ;;
        3)
            echo ""
            echo "请输入要执行的步骤编号（0-6，空格分隔多个步骤）："
            read -p "步骤编号: " manual_steps
            for s in $manual_steps; do
                sedi "/^$s$/d" "$STATE_FILE" 2>/dev/null || true
            done
            echo -e "${GREEN}✓${NC} 已标记步骤 $manual_steps 为待执行"
            ;;
        *)
            # 默认断点续传，什么都不做，后续步骤会自动跳过已完成项
            echo -e "${GREEN}✓${NC} 断点续传，跳过已完成步骤"
            ;;
    esac
fi

# 步骤 0：环境检查
if is_step_done 0; then
    echo ""
    echo -e "${GREEN}✓ [跳过]${NC} 步骤 0：环境检查（已完成）"
else
    step_title 0 "环境检查"

# 检查 Node.js
if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v)
    echo -e "${GREEN}✓${NC} Node.js 已安装: $NODE_VERSION"
else
    echo -e "${RED}✗${NC} Node.js 未安装"
    echo "  请先安装 Node.js: https://nodejs.org/"
    exit 1
fi

# 检查 npm
if command -v npm &> /dev/null; then
    NPM_VERSION=$(npm -v)
    echo -e "${GREEN}✓${NC} npm 已安装: $NPM_VERSION"
else
    echo -e "${RED}✗${NC} npm 未安装"
    exit 1
fi

# 检查 Git
if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version | head -1)
    echo -e "${GREEN}✓${NC} Git 已安装: $GIT_VERSION"
else
    echo -e "${RED}✗${NC} Git 未安装"
    exit 1
fi

# 检查 clawhub
if command -v clawhub &> /dev/null; then
    echo -e "${GREEN}✓${NC} clawhub 已安装"
    CLAWHUB_CMD="clawhub"
else
    echo -e "${YELLOW}⚠${NC} clawhub 未安装，将使用 npx"
    CLAWHUB_CMD="npx -y clawhub@latest"
fi

# 检查 Python3
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version 2>&1)
    echo -e "${GREEN}✓${NC} Python3 已安装: $PYTHON_VERSION"
else
    echo -e "${RED}✗${NC} Python3 未安装"
    echo "  请先安装 Python 3: https://www.python.org/"
    exit 1
fi

echo ""

mark_step_done 0
fi

if is_step_done 1; then
    echo ""
    echo -e "${GREEN}✓ [跳过]${NC} 步骤 1：安装 OpenClaw（已完成）"
else
# ═══════════════════════════════════════════════════════════════
# 步骤 1：安装 OpenClaw
# ═══════════════════════════════════════════════════════════════
step_title 1 "安装 OpenClaw"

# 动态获取可用版本
echo -e "${BLUE}正在获取可用版本列表...${NC}"
echo ""

RECOMMENDED_VERSION="2026.3.13"

# 从 npm 获取所有版本（最近15个）
AVAILABLE_VERSIONS=$(npm view openclaw versions --json 2>/dev/null | python3 -c "
import json, sys
try:
    versions = json.load(sys.stdin)
    if isinstance(versions, str):
        versions = [versions]
    # 过滤掉 alpha/beta/rc，取最近20个
    stable = [v for v in versions if not any(x in v.lower() for x in ['alpha', 'beta', 'rc'])]
    for v in stable[-20:]:
        print(v)
except:
    pass
" 2>/dev/null)

if [ -z "$AVAILABLE_VERSIONS" ]; then
    echo -e "${YELLOW}⚠ 无法获取版本列表，使用预设版本${NC}"
    AVAILABLE_VERSIONS="2026.3.13
2026.3.17
2026.3.23-2
2026.3.28
2026.2.28"
fi

# 显示版本列表
echo -e "${CYAN}请选择要安装的 OpenClaw 版本：${NC}"
echo ""

VERSION_ARRAY=()
IDX=1
RECOMMENDED_IDX=0

while IFS= read -r ver; do
    if [ -n "$ver" ]; then
        VERSION_ARRAY+=("$ver")
        if [ "$ver" = "$RECOMMENDED_VERSION" ]; then
            echo -e "  ${GREEN}$IDX${NC}) $ver  ${GREEN}★ 推荐${NC}"
            RECOMMENDED_IDX=$IDX
        else
            echo -e "  ${YELLOW}$IDX${NC}) $ver"
        fi
        ((IDX++))
    fi
done <<< "$AVAILABLE_VERSIONS"

CUSTOM_IDX=$IDX
echo -e "  ${BLUE}$IDX${NC}) 自定义版本号"
((IDX++))
LATEST_IDX=$IDX
echo -e "  ${RED}$IDX${NC}) latest（不推荐）"
echo ""

TOTAL_OPTIONS=$IDX
read -p "请输入选项 [1-$TOTAL_OPTIONS，默认$RECOMMENDED_IDX]: " version_choice

# 处理选择
if [ -z "$version_choice" ] || [ "$version_choice" = "$RECOMMENDED_IDX" ]; then
    OPENCLAW_VERSION="$RECOMMENDED_VERSION"
elif [ "$version_choice" -ge 1 ] 2>/dev/null && [ "$version_choice" -le ${#VERSION_ARRAY[@]} ] 2>/dev/null; then
    OPENCLAW_VERSION="${VERSION_ARRAY[$((version_choice-1))]}"
elif [ "$version_choice" = "$CUSTOM_IDX" ]; then
    echo ""
    read -p "请输入版本号 (例如: 2026.3.13): " custom_version
    if [ -n "$custom_version" ]; then
        OPENCLAW_VERSION="$custom_version"
    else
        OPENCLAW_VERSION="$RECOMMENDED_VERSION"
    fi
elif [ "$version_choice" = "$LATEST_IDX" ]; then
    echo ""
    echo -e "${RED}⚠️  警告：latest 版本可能存在兼容性问题！${NC}"
    read -p "确定要安装 latest 版本? [y/N]: " confirm_latest
    if [[ "$confirm_latest" =~ ^[Yy]$ ]]; then
        OPENCLAW_VERSION="latest"
    else
        echo -e "${YELLOW}已取消，使用推荐版本 $RECOMMENDED_VERSION${NC}"
        OPENCLAW_VERSION="$RECOMMENDED_VERSION"
    fi
else
    echo -e "${YELLOW}无效选项，使用推荐版本 $RECOMMENDED_VERSION${NC}"
    OPENCLAW_VERSION="$RECOMMENDED_VERSION"
fi

echo ""
echo -e "${GREEN}✓${NC} 选择安装版本: ${CYAN}$OPENCLAW_VERSION${NC}"
echo ""

echo "将执行以下操作："
echo "  1. 安装 OpenClaw $OPENCLAW_VERSION"
echo "  2. 运行 onboard 初始化"
echo ""

if confirm_continue; then
    echo -e "${BLUE}正在安装 OpenClaw $OPENCLAW_VERSION...${NC}"
    
    if [ "$OPENCLAW_VERSION" = "latest" ]; then
        npm install -g openclaw
    else
        npm install -g openclaw@$OPENCLAW_VERSION
    fi
    
    # 自动验证安装
    echo ""
    echo -e "${BLUE}🔍 验证安装...${NC}"
    if command -v openclaw &> /dev/null; then
        INSTALLED_VER=$(openclaw --version 2>&1 | head -1)
        echo -e "  ${GREEN}✓${NC} OpenClaw 已安装: $INSTALLED_VER"
    else
        echo -e "  ${RED}✗${NC} openclaw 命令未找到，安装可能失败"
        echo "  尝试检查 npm 全局目录: npm list -g openclaw"
        exit 1
    fi
    
    echo ""
    echo -e "${BLUE}初始化 OpenClaw...${NC}"
    echo -e "${YELLOW}请按照提示完成初始化配置${NC}"
    openclaw onboard --install-daemon
    
    echo ""
    echo -e "${GREEN}✓${NC} OpenClaw 安装完成"
else
    echo -e "${YELLOW}跳过 OpenClaw 安装${NC}"
fi
mark_step_done 1
fi

if is_step_done 2; then
    echo ""
    echo -e "${GREEN}✓ [跳过]${NC} 步骤 2：安装飞书插件（已完成）"
else
# ═══════════════════════════════════════════════════════════════
# 步骤 2：安装飞书插件（可选）
# ═══════════════════════════════════════════════════════════════
step_title 2 "安装飞书插件（可选）"

echo "如果您使用飞书（Lark/Feishu）作为消息渠道，可以安装飞书插件。"
echo ""
read -p "是否安装飞书插件? [y/N]: " install_feishu

if [[ "$install_feishu" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}正在安装飞书插件...${NC}"
    npx -y @larksuite/openclaw-lark install 2>&1 | tail -5
    LARK_EXIT=$?
    
    # 自动验证飞书插件
    echo ""
    echo -e "${BLUE}🔍 验证飞书插件...${NC}"
    if [ -d "$HOME/.openclaw/extensions/openclaw-lark" ]; then
        LARK_VER=$(cat "$HOME/.openclaw/extensions/openclaw-lark/package.json" 2>/dev/null | grep '"version"' | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')
        echo -e "  ${GREEN}✓${NC} 飞书插件已安装: ${LARK_VER:-未知版本}"
    else
        echo -e "  ${RED}✗${NC} 飞书插件安装可能失败"
    fi
    
    echo ""
    echo -e "${YELLOW}注意：飞书插件需要配置 App ID 和 App Secret${NC}"
    echo "  1. 访问飞书开放平台: https://open.feishu.cn/"
    echo "  2. 创建企业自建应用"
    echo "  3. 获取 App ID 和 App Secret"
    echo "  4. 编辑 ~/.openclaw/openclaw.json 添加配置"
else
    echo -e "${YELLOW}跳过飞书插件安装${NC}"
fi
mark_step_done 2
fi

if is_step_done 3; then
    echo ""
    echo -e "${GREEN}✓ [跳过]${NC} 步骤 3：配置子智能体（已完成）"
else
# ═══════════════════════════════════════════════════════════════
# 步骤 3：配置子智能体
# ═══════════════════════════════════════════════════════════════
step_title 3 "配置 8 个科研子智能体"

echo "将配置以下子智能体："
echo "  1. researcher   - 文献调研员"
echo "  2. idea         - 创意生成器"
echo "  3. mentor       - 导师审核员"
echo "  4. architect    - 架构设计师"
echo "  5. coder        - 实验工程师"
echo "  6. writer       - 论文撰写员"
echo "  7. reviewer     - 论文审稿人"
echo "  8. coordinator  - 科研主管"
echo ""

if confirm_continue; then
    # 检查并创建 .openclaw 目录
    if [ ! -d "$HOME/.openclaw" ]; then
        mkdir -p "$HOME/.openclaw"
    fi
    
    # 复制子智能体工作区
    echo "复制子智能体工作区..."
    for workspace in "$SCRIPT_DIR/4.子智能体/workspace-"*; do
        if [ -d "$workspace" ]; then
            name=$(basename "$workspace")
            target="$HOME/.openclaw/$name"
            
            if [ -d "$target" ]; then
                echo "  备份现有 $name"
                mv "$target" "${target}.backup.$(date +%Y%m%d_%H%M%S)"
            fi
            
            echo "  复制 $name"
            cp -r "$workspace" "$target"
        fi
    done
    
    # 自动合并子智能体配置到 openclaw.json
    echo ""
    echo "自动合并子智能体配置到 ~/.openclaw/openclaw.json ..."

    CONFIG_FILE="$HOME/.openclaw/openclaw.json"
    TEMPLATE_FILE="$SCRIPT_DIR/4.子智能体/agents_config.template.json"

    if [ -f "$TEMPLATE_FILE" ] && [ -f "$CONFIG_FILE" ]; then
        # 使用 Python 合并 agents.list
        python3 - "$CONFIG_FILE" "$TEMPLATE_FILE" "$HOME" << 'PYEOF'
import json, sys, os

config_path = sys.argv[1]
template_path = sys.argv[2]
home_dir = sys.argv[3]

# 读取现有配置
with open(config_path, 'r') as f:
    raw = f.read()

# openclaw.json 可能是 JSON5（含注释、尾逗号），用 json5 或清理后解析
try:
    import json5
    config = json5.loads(raw)
except ImportError:
    # 简单清理：去掉 // 注释和尾逗号
    import re
    lines = raw.split('\n')
    cleaned = []
    for line in lines:
        # 去行内 // 注释
        line = re.sub(r'//.*$', '', line)
        cleaned.append(line)
    text = '\n'.join(cleaned)
    # 去尾逗号
    text = re.sub(r',(\s*[}\]])', r'\1', text)
    config = json.loads(text)

# 读取模板
with open(template_path, 'r') as f:
    template = json.load(f)

# 替换 {{HOME}}
def replace_home(obj):
    if isinstance(obj, str):
        return obj.replace('{{HOME}}', home_dir)
    elif isinstance(obj, dict):
        return {k: replace_home(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [replace_home(item) for item in obj]
    return obj

template_agents = replace_home(template.get('agents', {}).get('list', []))

# 合并：已存在的按 id 覆盖，新的追加
existing = config.setdefault('agents', {}).setdefault('list', [])
existing_ids = {a['id'] for a in existing}

for agent in template_agents:
    if agent['id'] in existing_ids:
        # 更新已存在的（覆盖 workspace 和 agentDir）
        for i, a in enumerate(existing):
            if a['id'] == agent['id']:
                existing[i] = agent
                break
    else:
        existing.append(agent)

# 写回配置
with open(config_path, 'w') as f:
    json.dump(config, f, ensure_ascii=False, indent=2)

agent_ids = [a['id'] for a in existing]
print(f"  已合并 {len(template_agents)} 个子智能体配置")
print(f"  当前 agents.list: {', '.join(agent_ids)}")
PYEOF

        echo -e "${GREEN}✓${NC} 子智能体配置已自动合并到 ~/.openclaw/openclaw.json"

        # 同时保存一份 agents_config.json 备份
        sed "s|{{HOME}}|$HOME|g" "$TEMPLATE_FILE" > "$HOME/.openclaw/agents_config.json" 2>/dev/null || cp "$TEMPLATE_FILE" "$HOME/.openclaw/agents_config.json"
        echo -e "${GREEN}✓${NC} 配置备份已保存: ~/.openclaw/agents_config.json"
    else
        echo -e "${YELLOW}⚠ 未找到 openclaw.json 或模板，跳过自动合并${NC}"
        echo -e "${YELLOW}请手动将 agents 配置合并到 ~/.openclaw/openclaw.json${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}✓${NC} 子智能体配置完成"
else
    echo -e "${YELLOW}跳过子智能体配置${NC}"
fi

# 自动验证子智能体配置
echo ""
echo -e "${BLUE}🔍 验证子智能体配置...${NC}"
CONFIG_FILE="$HOME/.openclaw/openclaw.json"
if [ -f "$CONFIG_FILE" ]; then
    AGENT_COUNT=$(python3 -c "
import json, re, sys
try:
    import json5
    config = json5.loads(open('$CONFIG_FILE').read())
except ImportError:
    raw = open('$CONFIG_FILE').read()
    cleaned = '\n'.join([re.sub(r'//.*$', '', l) for l in raw.split('\n')])
    cleaned = re.sub(r',(\s*[}\]])', r'\1', cleaned)
    config = json.loads(cleaned)
agents = config.get('agents', {}).get('list', [])
ids = [a['id'] for a in agents]
print(len(ids))
for a_id in ids:
    a = next((x for x in agents if x['id'] == a_id), {})
    ws = a.get('workspace', 'N/A')
    print(f'  {a_id}: {ws}')
" 2>/dev/null)
    if [ -n "$AGENT_COUNT" ]; then
        AGENT_NUM=$(echo "$AGENT_COUNT" | head -1)
        echo -e "  ${GREEN}✓${NC} 共 $AGENT_NUM 个子智能体:"
        echo "$AGENT_COUNT" | tail -n +2 | while read -r line; do
            echo -e "    $line"
        done
    fi
fi

# 验证工作区目录
WORKSPACE_OK=true
for ws in researcher idea mentor architect coder writer reviewer coordinator; do
    if [ -d "$HOME/.openclaw/workspace-$ws" ]; then
        echo -e "  ${GREEN}✓${NC} workspace-$ws 存在"
    else
        echo -e "  ${YELLOW}⚠${NC} workspace-$ws 不存在"
        WORKSPACE_OK=false
    fi
done

mark_step_done 3
fi

if is_step_done 4; then
    echo ""
    echo -e "${GREEN}✓ [跳过]${NC} 步骤 4：安装技能（已完成）"
else
# ═══════════════════════════════════════════════════════════════
# 步骤 4：安装技能
# ═══════════════════════════════════════════════════════════════
step_title 4 "安装技能"

echo "将安装以下技能："
echo ""
echo -e "${CYAN}LabClaw (240个生物医学技能):${NC}"
echo "  - bio/ (86个)        - 生物学和生命科学"
echo "  - general/ (54个)    - 通用数据科学"
echo "  - literature/ (33个) - 文献检索"
echo "  - med/ (22个)        - 医学临床"
echo "  - pharma/ (36个)     - 药物研发"
echo "  - vision/ (5个)      - 视觉处理"
echo ""
echo -e "${CYAN}ClawHub 核心技能 (20+个):${NC}"
echo "  - arxiv-watcher, literature-review, perplexity"
echo "  - senior-architect, backend-patterns"
echo "  - test-runner, docker-essentials, wandb-monitor"
echo "  - ai-pdf-builder, typetex, chart-image"
echo "  - git-essentials, god-mode, api-gateway"
echo ""

if confirm_continue; then
    # 安装 LabClaw
    echo -e "${BLUE}安装 LabClaw...${NC}"
    if [ ! -d "$HOME/.openclaw/skills" ]; then
        mkdir -p "$HOME/.openclaw/skills"
    fi
    
    cd "$HOME/.openclaw/skills"
    
    if [ -d "LabClaw" ]; then
        echo -e "${YELLOW}LabClaw 已存在，更新中...${NC}"
        cd LabClaw && git pull && cd ..
    else
        echo "克隆 LabClaw 仓库..."
        git clone https://github.com/wu-yc/LabClaw.git
    fi
    
    echo "复制技能文件..."
    cp -r LabClaw/skills/* . 2>/dev/null || true
    echo -e "${GREEN}✓${NC} LabClaw 安装完成"
    
    # 安装 ClawHub 技能
    echo ""
    echo -e "${BLUE}安装 ClawHub 核心技能...${NC}"
    
    CLAWHUB_SKILLS=(
        "arxiv-watcher"
        "literature-review"
        "perplexity"
        "senior-architect"
        "backend-patterns"
        "test-runner"
        "docker-essentials"
        "wandb-monitor"
        "debug-pro"
        "ai-pdf-builder"
        "typetex"
        "chart-image"
        "nano-pdf"
        "project-context-sync"
        "prompt-log"
        "git-essentials"
        "get-tldr"
        "claude-optimised"
        "god-mode"
        "api-gateway"
        "openclaw-tavily-search"
        "multi-search-engine"
    )
    
    for skill in "${CLAWHUB_SKILLS[@]}"; do
        install_skill "$skill" "$CLAWHUB_CMD"
        sleep 0.5
    done
    
    echo ""
    echo -e "${GREEN}✓${NC} 技能安装完成"
    echo "  成功: $SKILLS_INSTALLED 个"
    echo "  失败: $SKILLS_FAILED 个"

    # 自动验证技能安装
    echo ""
    echo -e "${BLUE}🔍 验证技能安装...${NC}"
    SKILLS_DIR="$HOME/.openclaw/skills"
    if [ -d "$SKILLS_DIR" ]; then
        INSTALLED_SKILLS=$(ls -d "$SKILLS_DIR"/*/ 2>/dev/null | wc -l | tr -d ' ')
        echo -e "  ${GREEN}✓${NC} 技能目录共 $INSTALLED_SKILLS 个技能"
        # 检查关键技能
        for check_skill in arxiv-watcher tavily-search multi-search-engine LabClaw; do
            if ls -d "$SKILLS_DIR"/*/"$check_skill"* "$SKILLS_DIR/$check_skill"* 2>/dev/null | head -1 > /dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} $check_skill"
            else
                echo -e "  ${YELLOW}⚠${NC} $check_skill 未找到（可能已安装到其他位置）"
            fi
        done
    fi

    # 自动配置浏览器和搜索
    echo ""
    echo -e "${BLUE}配置浏览器和搜索...${NC}"

    CONFIG_FILE="$HOME/.openclaw/openclaw.json"

    # 1. 关闭默认 web search，避免和 tavily 冲突
    python3 - "$CONFIG_FILE" << 'PYEOF2'
import json, sys, re

config_path = sys.argv[1]

with open(config_path, 'r') as f:
    raw = f.read()

try:
    import json5
    config = json5.loads(raw)
except ImportError:
    lines = raw.split('\n')
    cleaned = [re.sub(r'//.*$', '', l) for l in lines]
    text = '\n'.join(cleaned)
    text = re.sub(r',(\s*[}\]])', r'\1', text)
    config = json.loads(text)

# 设置 tools.profile = "full"
tools = config.setdefault('tools', {})
tools['profile'] = 'full'

# 关闭默认 web search
web = tools.setdefault('web', {})
search = web.setdefault('search', {})
search['enabled'] = False

with open(config_path, 'w') as f:
    json.dump(config, f, ensure_ascii=False, indent=2)

print("  ✓ tools.profile = full")
print("  ✓ tools.web.search.enabled = false")
PYEOF2

    echo -e "${GREEN}✓${NC} 浏览器和搜索配置完成"

    # 2. 写入 TOOLS.md 搜索配置
    WORKSPACE="$HOME/.openclaw/workspace"
    TOOLS_FILE="$WORKSPACE/TOOLS.md"

    if [ ! -f "$TOOLS_FILE" ]; then
        cat > "$TOOLS_FILE" << 'TOOLSEOF'
# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics - the stuff that's unique to your setup.

## Web Search

Use the openclaw-tavily-search skill as the top-priority search tool when doing web search.

If the question requires searching for more relevant knowledge, use multi-search-engine skill as an alternative solution.
TOOLSEOF
        echo -e "${GREEN}✓${NC} 已创建 TOOLS.md 搜索配置"
    else
        if ! grep -q "openclaw-tavily-search" "$TOOLS_FILE" 2>/dev/null; then
            cat >> "$TOOLS_FILE" << 'TOOLSEOF'

## Web Search

Use the openclaw-tavily-search skill as the top-priority search tool when doing web search.

If the question requires searching for more relevant knowledge, use multi-search-engine skill as an alternative solution.
TOOLSEOF
            echo -e "${GREEN}✓${NC} 已追加搜索配置到 TOOLS.md"
        else
            echo -e "${GREEN}✓${NC} TOOLS.md 已包含搜索配置"
        fi
    fi

else
    echo -e "${YELLOW}跳过技能安装${NC}"
fi
mark_step_done 4
fi

if is_step_done 5; then
    echo ""
    echo -e "${GREEN}✓ [跳过]${NC} 步骤 5：配置 API Key（已完成）"
else
# ═══════════════════════════════════════════════════════════════
# 步骤 5：配置 API Key
# ═══════════════════════════════════════════════════════════════
step_title 5 "配置 API Key"

ENV_FILE="$HOME/.openclaw/.env"

# 确保目录存在
mkdir -p "$HOME/.openclaw"

# 如果 .env 不存在，创建一个
if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" << 'ENVEOF'
# XClaw API Keys
# 自动被 send_email.py 和各技能读取

# 邮件发送（必填）
MATON_API_KEY=

# AI 搜索（可选）
TAVILY_API_KEY=

# 论文图表（可选）
POYO_API_KEY=

# 千问 LLM（可选，已有默认值）
# LLM_API_KEY=sk-xxx
# LLM_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1
# LLM_MODEL=qwen3.5-plus
ENVEOF
    echo -e "${GREEN}✓${NC} 已创建 ~/.openclaw/.env"
else
    echo -e "${GREEN}✓${NC} ~/.openclaw/.env 已存在"
fi

# 交互式填写 API Key
echo "请依次输入以下 API Key（留空则跳过）："
echo ""
echo -e "${CYAN}获取链接：${NC}"
echo "  MATON_API_KEY → https://maton.ai"
echo "  TAVILY_API_KEY → https://tavily.com"
echo "  POYO_API_KEY   → https://poyo.ai"
echo ""

# MATON_API_KEY
read -p "MATON_API_KEY (邮件发送，访问 https://maton.ai 获取): " maton_key
if [ -n "$maton_key" ]; then
    if grep -q "MATON_API_KEY=" "$ENV_FILE"; then
        sedi "s|^MATON_API_KEY=.*|MATON_API_KEY=$maton_key|" "$ENV_FILE"
    else
        echo "MATON_API_KEY=$maton_key" >> "$ENV_FILE"
    fi
    echo -e "${GREEN}✓${NC} MATON_API_KEY 已保存"
fi

# TAVILY_API_KEY
read -p "TAVILY_API_KEY (网络搜索，可选，访问 https://tavily.com 获取): " tavily_key
if [ -n "$tavily_key" ]; then
    if grep -q "TAVILY_API_KEY=" "$ENV_FILE"; then
        sedi "s|^TAVILY_API_KEY=.*|TAVILY_API_KEY=$tavily_key|" "$ENV_FILE"
    else
        echo "TAVILY_API_KEY=$tavily_key" >> "$ENV_FILE"
    fi
    echo -e "${GREEN}✓${NC} TAVILY_API_KEY 已保存"
fi

# POYO_API_KEY
read -p "POYO_API_KEY (论文图表，可选，访问 https://poyo.ai 获取): " poyo_key
if [ -n "$poyo_key" ]; then
    if grep -q "POYO_API_KEY=" "$ENV_FILE"; then
        sedi "s|^POYO_API_KEY=.*|POYO_API_KEY=$poyo_key|" "$ENV_FILE"
    else
        echo "POYO_API_KEY=$poyo_key" >> "$ENV_FILE"
    fi
    echo -e "${GREEN}✓${NC} POYO_API_KEY 已保存"
fi

echo ""
echo -e "${GREEN}✓${NC} API Key 配置完成（配置保存在 ~/.openclaw/.env）"
echo -e "${YELLOW}提示：如需修改，可直接编辑 ~/.openclaw/.env${NC}"
mark_step_done 5
fi

if is_step_done 6; then
    echo ""
    echo -e "${GREEN}✓ [跳过]${NC} 步骤 6：重启 Gateway（已完成）"
else
# ═══════════════════════════════════════════════════════════════
# 步骤 6：重启 Gateway
# ═══════════════════════════════════════════════════════════════
step_title 6 "重启 OpenClaw Gateway"

echo "即将重启 Gateway 以加载新配置和技能。"
echo ""
read -p "是否立即重启 Gateway? [y/N]: " restart_gateway

if [[ "$restart_gateway" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}正在重启 Gateway...${NC}"

    if command -v openclaw &> /dev/null; then
        openclaw gateway restart 2>&1 || true
        sleep 3

        # 自动验证 Gateway 状态
        echo ""
        echo -e "${BLUE}🔍 验证 Gateway 状态...${NC}"
        GW_STATUS=$(openclaw gateway status 2>&1)
        if echo "$GW_STATUS" | grep -qi "running\|active\|pid"; then
            GW_PID=$(echo "$GW_STATUS" | grep -oi "pid.*[0-9]*" | head -1)
            echo -e "  ${GREEN}✓${NC} Gateway 运行中 ${GW_PID}"
        else
            echo -e "  ${YELLOW}⚠${NC} Gateway 状态异常，请手动检查:"
            echo "    openclaw gateway status"
            echo "    openclaw gateway start"
        fi
    else
        echo -e "${RED}✗${NC} openclaw 命令未找到，请手动重启："
        echo "  openclaw gateway restart"
    fi
else
    echo -e "${YELLOW}跳过 Gateway 重启${NC}"
    echo ""
    echo -e "${CYAN}您可以稍后手动重启：${NC}"
    echo "  openclaw gateway restart"
fi
mark_step_done 6
fi

echo ""
print_line
echo -e "${GREEN}🎉 XClaw 配置全部完成！${NC}"
print_line
echo ""

echo -e "${CYAN}下一步操作：${NC}"
echo "1. 重新加载 Shell 配置: source ~/.bashrc (或 ~/.zshrc)"
echo "2. 检查 OpenClaw 状态: openclaw status"
echo "3. 查看完整文档: cat README.md"
echo "4. 修改 API Key: 编辑 ~/.openclaw/.env"

if [ -d "$BACKUP_DIR" ]; then
    echo ""
    echo -e "${CYAN}备份位置: $BACKUP_DIR${NC}"
fi

# 全部完成，清除断点状态
if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE"
    echo ""
    echo -e "${GREEN}✓${NC} 已清除断点续传状态"
fi

echo ""
