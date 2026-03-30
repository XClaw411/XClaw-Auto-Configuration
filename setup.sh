#!/bin/bash
# XClaw 交互式一键配置脚本
# 自动完成 1-4 部分配置，并引导输入 API Key

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
        echo -e "${GREEN}✓${NC} 配置已备份到: ${CYAN}$BACKUP_DIR${NC}"
        
        # 显示备份内容
        echo ""
        echo "备份内容包括："
        du -sh "$BACKUP_DIR" 2>/dev/null || true
        echo ""
        
        # 询问是否查看备份详情
        read -p "是否查看备份目录结构? [y/N]: " view_backup
        if [[ "$view_backup" =~ ^[Yy]$ ]]; then
            echo ""
            ls -la "$BACKUP_DIR" | head -20
            echo ""
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
    
    echo ""
    echo -e "${GREEN}✓${NC} 卸载完成"
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
    
    echo ""
    echo -e "${GREEN}✓${NC} 卸载完成"
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
    
    # 删除配置（可选，会询问）
    if [ -d "$HOME/.openclaw" ]; then
        echo ""
        read -p "删除配置目录 ~/.openclaw? [y/N]: " del_config
        if [[ "$del_config" =~ ^[Yy]$ ]]; then
            rm -rf "$HOME/.openclaw"
            echo -e "${GREEN}✓${NC} 配置已删除"
        else
            echo -e "${YELLOW}保留配置目录${NC}"
        fi
    fi
    
    # 清理缓存
    rm -rf "$HOME/.npm/_npx" 2>/dev/null || true
    rm -rf /tmp/openclaw* 2>/dev/null || true
}

# 执行检测和卸载
check_and_uninstall_openclaw

# 步骤 0：环境检查
echo ""
echo -e "${CYAN}🔍 环境检查${NC}"
echo ""

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

echo ""

# ═══════════════════════════════════════════════════════════════
# 步骤 1：安装 OpenClaw
# ═══════════════════════════════════════════════════════════════
step_title 1 "安装 OpenClaw"

# 版本选择器
echo -e "${CYAN}请选择要安装的 OpenClaw 版本：${NC}"
echo ""
echo -e "  ${GREEN}1${NC}) 2026.3.13  - 推荐稳定版（默认）"
echo -e "  ${YELLOW}2${NC}) 2026.3.17  - 较新版本"
echo -e "  ${YELLOW}3${NC}) 2026.2.28  - 旧稳定版"
echo -e "  ${BLUE}4${NC}) 其他版本   - 自定义版本号"
echo -e "  ${RED}5${NC}) latest     - 最新版（不推荐）"
echo ""
read -p "请输入选项 [1-5，默认1]: " version_choice

# 设置默认版本
OPENCLAW_VERSION="2026.3.13"

case $version_choice in
    2)
        OPENCLAW_VERSION="2026.3.17"
        ;;
    3)
        OPENCLAW_VERSION="2026.2.28"
        ;;
    4)
        echo ""
        read -p "请输入版本号 (例如: 2026.3.13): " custom_version
        if [ -n "$custom_version" ]; then
            OPENCLAW_VERSION="$custom_version"
        fi
        ;;
    5)
        echo ""
        echo -e "${RED}⚠️  警告：latest 版本可能存在兼容性问题！${NC}"
        read -p "确定要安装 latest 版本? [y/N]: " confirm_latest
        if [[ "$confirm_latest" =~ ^[Yy]$ ]]; then
            OPENCLAW_VERSION="latest"
        else
            echo -e "${YELLOW}已取消，使用默认稳定版 2026.3.13${NC}"
            OPENCLAW_VERSION="2026.3.13"
        fi
        ;;
    *)
        # 默认使用 2026.3.13
        OPENCLAW_VERSION="2026.3.13"
        ;;
esac

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
    
    echo ""
    echo -e "${BLUE}初始化 OpenClaw...${NC}"
    echo -e "${YELLOW}请按照提示完成初始化配置${NC}"
    openclaw onboard --install-daemon
    
    echo ""
    echo -e "${GREEN}✓${NC} OpenClaw 安装完成"
else
    echo -e "${YELLOW}跳过 OpenClaw 安装${NC}"
fi

# ═══════════════════════════════════════════════════════════════
# 步骤 2：安装飞书插件（可选）
# ═══════════════════════════════════════════════════════════════
step_title 2 "安装飞书插件（可选）"

echo "如果您使用飞书（Lark/Feishu）作为消息渠道，可以安装飞书插件。"
echo ""
read -p "是否安装飞书插件? [y/N]: " install_feishu

if [[ "$install_feishu" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}正在安装飞书插件...${NC}"
    npx -y @larksuite/openclaw-lark@2026.3.17 install
    echo -e "${GREEN}✓${NC} 飞书插件安装完成"
    
    echo ""
    echo -e "${YELLOW}注意：飞书插件需要配置 App ID 和 App Secret${NC}"
    echo "  1. 访问飞书开放平台: https://open.feishu.cn/"
    echo "  2. 创建企业自建应用"
    echo "  3. 获取 App ID 和 App Secret"
    echo "  4. 编辑 ~/.openclaw/openclaw.json 添加配置"
else
    echo -e "${YELLOW}跳过飞书插件安装${NC}"
fi

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
    
    # 生成配置文件
    echo ""
    echo "生成 OpenClaw 配置文件..."
    if [ -f "$SCRIPT_DIR/4.子智能体/agents_config.template.json" ]; then
        sed "s|{{HOME}}|$HOME|g" "$SCRIPT_DIR/4.子智能体/agents_config.template.json" > "$HOME/.openclaw/agents_config.json"
        echo -e "${GREEN}✓${NC} 配置文件已生成: ~/.openclaw/agents_config.json"
        echo ""
        echo -e "${YELLOW}重要：请手动将 agents 配置合并到 ~/.openclaw/openclaw.json${NC}"
        echo "  可以参考: ~/.openclaw/agents_config.json"
    else
        echo -e "${YELLOW}⚠ 未找到配置模板，请手动复制配置${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}✓${NC} 子智能体配置完成"
else
    echo -e "${YELLOW}跳过子智能体配置${NC}"
fi

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
    )
    
    for skill in "${CLAWHUB_SKILLS[@]}"; do
        install_skill "$skill" "$CLAWHUB_CMD"
        sleep 0.5
    done
    
    echo ""
    echo -e "${GREEN}✓${NC} 技能安装完成"
    echo "  成功: $SKILLS_INSTALLED 个"
    echo "  失败: $SKILLS_FAILED 个"
else
    echo -e "${YELLOW}跳过技能安装${NC}"
fi

echo ""
print_line
echo -e "${GREEN}🎉 XClaw 配置完成！${NC}"
print_line
echo ""

echo -e "${CYAN}下一步操作：${NC}"
echo "1. 重新加载 Shell 配置: source ~/.bashrc (或 ~/.zshrc)"
echo "2. 检查 OpenClaw 状态: openclaw status"
echo "3. 查看完整文档: cat README.md"

if [ -d "$BACKUP_DIR" ]; then
    echo ""
    echo -e "${CYAN}备份位置: $BACKUP_DIR${NC}"
fi

echo ""
