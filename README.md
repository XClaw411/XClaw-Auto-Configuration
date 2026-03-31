# XClaw 自动配置指南

> 🦞 一键复刻完整的 OpenClaw 科研助手配置

---

## 📋 项目概述

本项目提供了一套完整的 OpenClaw 配置方案，专为科研工作流程设计，包含：

- ✅ 8 个科研专用子智能体（文献调研 → 论文审稿全流程）
- ✅ 265+ 个技能（LabClaw 240个 + ClawHub 25+个）
- ✅ 完整的论文工作流自动化
- ✅ API 网关集成（邮件、搜索、论文图表）
- ✅ 断点续传支持（中断后可从断点继续）

**适用场景：**
- 学术研究全流程管理
- 论文撰写与审稿
- 实验设计与代码实现
- 科研热点邮件推送

---

## 🚀 快速开始

### 一键配置（推荐 ⭐）

```bash
# 1. 克隆仓库
git clone https://github.com/inyvn-claw/XClaw-Auto-Configuration.git
cd XClaw-Auto-Configuration

# 2. 运行交互式配置脚本
./setup.sh
```

**`setup.sh` 自动完成 6 步配置：**

| 步骤 | 内容 | 说明 |
|------|------|------|
| 0 | 环境检查 | Node.js / npm / Git / Python3 / clawhub |
| 1 | 安装 OpenClaw | 动态获取版本列表，推荐 2026.3.13 |
| 2 | 安装飞书插件 | 可选，自动验证安装 |
| 3 | 配置 8 个子智能体 | 自动合并配置到 openclaw.json |
| 4 | 安装 265+ 技能 | LabClaw + ClawHub + 搜索技能，自动配置 TOOLS.md |
| 5 | 配置 API Key | 保存到 `~/.openclaw/.env`，含获取链接 |
| 6 | 重启 Gateway | 自动重启并验证运行状态 |

**每步执行完自动验证，无需手动检查！**

### 断点续传

如果脚本中断（网络问题、手动 Ctrl+C 等），重新运行 `./setup.sh` 会自动检测断点：

```
🔄 检测到上次未完成的配置

📋 步骤进度：
  ✓ 步骤 0: 环境检查
  ✓ 步骤 1: 安装 OpenClaw
  ○ 步骤 2: 安装飞书插件
  ○ 步骤 3: 配置子智能体
  ...

请选择：
  1) 断点续传 — 跳过已完成的步骤，从断点继续（推荐）
  2) 全部重来 — 清除进度，从头开始
  3) 仅执行指定步骤
```

---

## 📁 项目结构

```
XClaw-Auto-Configuration/
├── README.md                      # 本文件
├── setup.sh                       # ⭐ 交互式一键配置脚本（断点续传）
├── install.sh                     # 非交互式安装脚本
├── validate.sh                    # 配置验证脚本
├── .env                           # API Key 配置模板
├── LICENSE                        # MIT 许可证
├── .gitignore                     # Git 忽略规则
│
├── 1. 卸载旧版本和安装指定版本XClaw/
│   ├── README.md
│   └── uninstall_claw.sh
│
├── 2.浏览器控制和联网搜索/
│   └── README.md
│
├── 3.skills/
│   ├── README.md
│   ├── 邮件推送/
│   │   ├── README.md
│   │   └── send_email.py          # RSS 论文推送 + LLM 摘要 + 邮件发送
│   └── 生成论文图/
│       └── README.md
│
├── 4.子智能体/
│   ├── README.md
│   ├── 子智能体技能配置指南.md
│   ├── skills-科研.md
│   ├── agents_config.template.json
│   ├── workspace-researcher/      # 文献调研员
│   ├── workspace-idea/            # 创意生成器
│   ├── workspace-mentor/          # 导师审核员
│   ├── workspace-architect/       # 架构设计师
│   ├── workspace-coder/           # 实验工程师
│   ├── workspace-writer/          # 论文撰写员
│   ├── workspace-reviewer/        # 论文审稿人
│   └── workspace-coordinator/     # 科研主管
│
└── 5.科研协作平台/
    └── README.md
```

---

## 🔧 API Key 配置

配置文件位于 `~/.openclaw/.env`，脚本会自动创建和填写：

```bash
# 邮件发送（必填）
MATON_API_KEY=          # https://maton.ai

# AI 搜索（可选）
TAVILY_API_KEY=         # https://tavily.com

# 论文图表（可选）
POYO_API_KEY=           # https://poyo.ai

# 千问 LLM（可选，已有默认值）
# LLM_API_KEY=sk-xxx
```

---

## 🎯 使用方法

### 启动科研工作流

```
@coordinator 我想写一篇关于深度学习的论文，请协调各子智能体完成
```

### 单独使用子智能体

```
@researcher 调研 Transformer 在计算机视觉中的最新进展
@writer 根据实验结果撰写方法章节
```

### 邮件推送

```bash
python3 3.skills/邮件推送/send_email.py
```

---

## 🔧 故障排查

```bash
# 检查 OpenClaw 状态
openclaw status

# 查看 Gateway 日志
openclaw logs --follow

# 检查技能安装
clawhub list

# 检查 API Key
cat ~/.openclaw/.env

# 重新运行配置
./setup.sh
```

---

## 📚 相关文档

| 文档 | 说明 |
|------|------|
| [OpenClaw 官方文档](https://docs.openclaw.ai/) | OpenClaw 使用指南 |
| [ClawHub 技能市场](https://clawhub.com/) | 技能搜索和安装 |
| [LabClaw 技能库](https://github.com/wu-yc/LabClaw) | 240 个生物医学技能 |
| [Maton API Gateway](https://maton.ai/) | 邮件发送服务 |

---

## 🛠️ 可用脚本

| 脚本 | 用途 |
|------|------|
| `setup.sh` | ⭐ **交互式一键配置**（断点续传、自动验证） |
| `install.sh` | 非交互式批量安装 |
| `validate.sh` | 配置验证检查 |
| `uninstall_claw.sh` | 卸载 OpenClaw |

---

## 📝 贡献指南

欢迎提交 Issue 和 PR！请确保：
- 配置文件不包含敏感信息（API Key、Token）
- 文档清晰易懂
- 脚本经过测试

---

## 📄 许可证

[MIT License](./LICENSE)

---

*最后更新：2026-03-31*
