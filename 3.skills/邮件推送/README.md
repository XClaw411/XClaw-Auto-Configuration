# 📬 邮件推送

科研热点邮件自动推送功能模块。

## 安装前依赖

本模块依赖 `rss-ai-reader` 技能，请先强制安装：

```
clawhub install rss-ai-reader --force
```

或在 ClawHub 中搜索安装 `rss-ai-reader`。

## 文件说明

- `send_email.py` — 主推送脚本（RSS 多源获取 + LLM 中文摘要 + 邮件发送）

## 环境变量

在项目根目录 `.env` 中配置：

```
MATON_API_KEY=你的密钥
TAVILY_API_KEY=你的密钥（可选）
```
