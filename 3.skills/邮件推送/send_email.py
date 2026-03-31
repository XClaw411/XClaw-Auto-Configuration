#!/usr/bin/env python3
"""
AGI&FBHC 科研热点推送 - RSS多源获取 + LLM中文摘要 + 正式模板
3个方向 × 3篇论文 = 9篇精选
样式对齐 3.26 正式版：精准关键词 + 核心看点
修改：逐个收件人发送，每封间隔2秒
"""
import urllib.request
import urllib.parse
import json
import re
import os
import sys
import ssl
import time
import hashlib
import html as html_module
from datetime import datetime, date, timedelta

# feedparser 从 rss-reader 虚拟环境加载
VENV_SITE = os.path.expanduser("~/rss-reader/venv/lib/python3.12/site-packages")
if os.path.isdir(VENV_SITE):
    sys.path.insert(0, VENV_SITE)

try:
    import feedparser
    HAS_FEEDPARSER = True
except ImportError:
    HAS_FEEDPARSER = False

# ===================== 自动加载 .env =====================
def load_dotenv(env_path):
    """从 .env 文件加载环境变量"""
    if not os.path.isfile(env_path):
        return
    with open(env_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if '=' in line:
                key, _, value = line.partition('=')
                key = key.strip()
                value = value.strip().strip('"').strip("'")
                if key and value and key not in os.environ:
                    os.environ[key] = value

# 优先加载 ~/.openclaw/.env，其次项目根目录 .env
load_dotenv(os.path.expanduser("~/.openclaw/.env"))
load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".env"))

MATON_API_KEY = os.environ.get("MATON_API_KEY", "")
RECIPIENTS = [
    "yanghailong@stu.jiangnan.edu.cn",
    "yanghailong86001@gmail.com",
    "dengzhaohong@jiangnan.edu.cn",
    "zhaorenhuo@stu.jiangnan.edu.cn",
    "shihaijun@stu.jiangnan.edu.cn",
    "gumingxian@stu.jiangnan.edu.cn",
    "wangjianqi@stu.jiangnan.edu.cn",
    "longwu@stu.jiangnan.edu.cn",
    "songze@stu.jiangnan.edu.cn",
    "huac@jsit.edu.cn",
    "985048739@qq.com",
    "1106503704@qq.com",
    "598502790@qq.com",
]

# 千问 LLM 配置
LLM_API_KEY = os.environ.get("LLM_API_KEY", "sk-762fba06d1314714aa14f35b450e286d")
LLM_BASE_URL = os.environ.get("LLM_BASE_URL", "https://dashscope.aliyuncs.com/compatible-mode/v1")
LLM_MODEL = os.environ.get("LLM_MODEL", "qwen3.5-plus")

# ===================== 3个方向的 RSS 源 =====================
FEEDS = {
    "ai": {
        "label": "🤖 LLM智能体",
        "icon": "📚",
        "color": "#3182CE",
        "link_bg": "#EBF8FF",
        "link_color": "#2B6CB0",
        "kw_bg": "#E6FFFA",
        "kw_color": "#2C7A7B",
        "card_bg": "#F8FAFC",
        "card_border": "#E2E8F0",
        "sources": [
            {"name": "arXiv - NLP/LLM", "url": "https://rss.arxiv.org/rss/cs.CL"},
            {"name": "arXiv - Machine Learning", "url": "https://rss.arxiv.org/rss/cs.LG"},
            {"name": "arXiv - AI", "url": "https://rss.arxiv.org/rss/cs.AI"},
            {"name": "arXiv - Computer Vision", "url": "https://rss.arxiv.org/rss/cs.CV"},
            {"name": "Nature Machine Intelligence", "url": "https://www.nature.com/natmachintell.rss"},
            {"name": "Google AI Blog", "url": "https://blog.research.google/feeds/posts/default"},
            {"name": "OpenAI Blog", "url": "https://openai.com/blog/rss.xml"},
            {"name": "Hugging Face Blog", "url": "https://huggingface.co/blog/feed.xml"},
        ]
    },
    "medicine": {
        "label": "🩺 医学前沿",
        "icon": "🏥",
        "color": "#E53E3E",
        "link_bg": "#FFF5F5",
        "link_color": "#C53030",
        "kw_bg": "#FED7D7",
        "kw_color": "#C53030",
        "card_bg": "#FFF5F5",
        "card_border": "#FED7D7",
        "sources": [
            {"name": "NEJM", "url": "https://www.nejm.org/action/showFeed?jc=nejm&type=etoc&feed=rss"},
            {"name": "The Lancet", "url": "https://www.thelancet.com/rssfeed/lancet_current.xml"},
            {"name": "BMJ", "url": "https://www.bmj.com/rss/recent.xml"},
            {"name": "JAMA", "url": "https://jamanetwork.com/rss/site_3/67.xml"},
            {"name": "Nature Medicine", "url": "https://www.nature.com/nm.rss"},
            {"name": "Lancet Digital Health", "url": "https://www.thelancet.com/rssfeed/landig_current.xml"},
            {"name": "npj Digital Medicine", "url": "https://www.nature.com/npjdigitalmed.rss"},
        ]
    },
    "bio": {
        "label": "🧬 蛋白质与酶",
        "icon": "🔬",
        "color": "#38A169",
        "link_bg": "#F0FFF4",
        "link_color": "#276749",
        "kw_bg": "#C6F6D5",
        "kw_color": "#276749",
        "card_bg": "#F0FFF4",
        "card_border": "#C6F6D5",
        "sources": [
            {"name": "Genome Biology", "url": "https://genomebiology.biomedcentral.com/articles/most-recent/rss.xml"},
            {"name": "PLOS Computational Biology", "url": "https://journals.plos.org/ploscompbiol/feed/atom"},
            {"name": "Nature Biotechnology", "url": "https://www.nature.com/nbt.rss"},
            {"name": "Nature Methods", "url": "https://www.nature.com/nmeth.rss"},
            {"name": "Nature Genetics", "url": "https://www.nature.com/ng.rss"},
            {"name": "Cell", "url": "https://www.cell.com/cell/current.rss"},
            {"name": "Science", "url": "https://www.science.org/action/showFeed?type=etoc&feed=rss&jc=science"},
            {"name": "Nature", "url": "https://www.nature.com/nature.rss"},
        ]
    }
}


def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)


def format_date_cn(date_str=None):
    try:
        if date_str:
            d = datetime.strptime(str(date_str)[:10], "%Y-%m-%d")
        else:
            d = datetime.now()
        return d.strftime("%Y-%m-%d")
    except:
        return datetime.now().strftime("%Y-%m-%d")


def clean_html(raw):
    text = re.sub(r'<[^>]+>', '', raw)
    text = html_module.unescape(text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text


# ===================== 论文去重（每日不重复） =====================
SENT_HISTORY_PATH = os.path.expanduser("~/.openclaw/email/sent_papers.json")

def paper_hash(title):
    """用标题生成唯一标识"""
    normalized = re.sub(r'\s+', ' ', title.strip().lower())
    return hashlib.md5(normalized.encode('utf-8')).hexdigest()[:12]

def load_sent_history():
    """加载已推送记录"""
    if not os.path.exists(SENT_HISTORY_PATH):
        return {}
    try:
        with open(SENT_HISTORY_PATH, 'r') as f:
            data = json.load(f)
        # 清理30天前的记录
        cutoff = (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d')
        cleaned = {k: v for k, v in data.items() if v.get('date', '') >= cutoff}
        return cleaned
    except:
        return {}

def save_sent_history(history):
    """保存已推送记录"""
    with open(SENT_HISTORY_PATH, 'w', encoding='utf-8') as f:
        json.dump(history, f, ensure_ascii=False, indent=2)

def is_paper_sent(title, history):
    """检查论文是否已推送过"""
    return paper_hash(title) in history

def mark_paper_sent(title, history):
    """标记论文为已推送"""
    history[paper_hash(title)] = {
        'title': title[:80],
        'date': datetime.now().strftime('%Y-%m-%d')
    }


# ===================== 渠道去重 + 顶刊优先 =====================
def get_channel(source_name):
    """将源名映射到渠道组（同平台不同子分类合并）"""
    if source_name.startswith('arXiv'):
        return 'arXiv'
    return source_name

def source_priority(source_name):
    """顶刊优先级（越小越高）"""
    # Tier 1: 四大顶刊 + 医学四大刊（完整名匹配）
    tier1 = {'Nature', 'Science', 'Cell', 'NEJM', 'The Lancet', 'JAMA', 'BMJ'}
    if source_name in tier1:
        return 1
    # Tier 2: Nature/Lancet 子刊
    tier2_kw = ['Nature ', 'Lancet ', 'Genome Biology', 'npj ']
    for kw in tier2_kw:
        if kw in source_name:
            return 2
    # Tier 3: 其他同行评审期刊
    if 'PLOS' in source_name:
        return 3
    # Tier 4: arXiv 预印本
    if 'arXiv' in source_name:
        return 4
    # Tier 5: 博客等
    return 5


# ===================== 千问 LLM 摘要生成 =====================
def llm_generate(title, abstract, direction_hint=""):
    """调用千问生成中文核心看点 + 关键词标签"""
    prompt = f"""请为以下学术论文生成中文核心看点和关键词标签。

标题：{title}
摘要：{abstract[:800]}
方向提示：{direction_hint}

请严格按以下JSON格式输出（不要添加其他内容，不要用markdown代码块包裹）：
{{"keywords": ["关键词1", "关键词2", "关键词3", "关键词4"], "summary": "中文核心看点，2-3句话，突出论文的创新点和实际意义。不超过150字。"}}"""

    payload = {
        "model": LLM_MODEL,
        "max_tokens": 300,
        "messages": [{"role": "user", "content": prompt}]
    }

    try:
        data = json.dumps(payload, ensure_ascii=False).encode('utf-8')
        req = urllib.request.Request(
            f"{LLM_BASE_URL}/chat/completions",
            data=data, method='POST'
        )
        req.add_header('Authorization', f'Bearer {LLM_API_KEY}')
        req.add_header('Content-Type', 'application/json')

        ctx = ssl.create_default_context()
        resp = urllib.request.urlopen(req, timeout=300, context=ctx)
        result = json.loads(resp.read().decode('utf-8'))

        content = result['choices'][0]['message']['content'].strip()
        # 清理可能的 markdown 代码块包裹
        content = re.sub(r'^```json\s*', '', content)
        content = re.sub(r'\s*```$', '', content)
        content = content.strip()

        parsed = json.loads(content)
        return {
            'keywords': parsed.get('keywords', ['前沿研究'])[:4],
            'summary': parsed.get('summary', abstract[:200])
        }
    except Exception as e:
        log(f"      LLM 失败: {e}")
        return None


# ===================== RSS 获取 =====================
def fetch_rss_papers(sources, max_per_source=5):
    if not HAS_FEEDPARSER:
        log("  ⚠ feedparser 不可用")
        return []

    all_papers = []
    for src in sources:
        try:
            log(f"    [{src['name']}]...")
            feed = feedparser.parse(src['url'])
            if hasattr(feed, 'status') and feed.status == 304:
                continue

            count = 0
            for entry in feed.entries[:max_per_source]:
                title = entry.get('title', '').strip().replace('\n', ' ')
                if not title:
                    continue
                link = entry.get('link', '')

                content = ''
                if hasattr(entry, 'content') and entry.content:
                    content = entry.content[0].get('value', '')
                elif hasattr(entry, 'summary'):
                    content = entry.summary
                elif hasattr(entry, 'description'):
                    content = entry.description
                content = clean_html(content)
                if len(content) > 1000:
                    content = content[:1000]

                arxiv_id = ''
                if 'arxiv.org' in link:
                    m = re.search(r'(\d{4}\.\d{4,5})', link)
                    if m:
                        arxiv_id = m.group(1)

                # 提取日期
                pub_date = ''
                if hasattr(entry, 'published_parsed') and entry.published_parsed:
                    try:
                        pub_date = datetime(*entry.published_parsed[:6]).strftime('%Y-%m-%d')
                    except:
                        pass
                if not pub_date and hasattr(entry, 'updated_parsed') and entry.updated_parsed:
                    try:
                        pub_date = datetime(*entry.updated_parsed[:6]).strftime('%Y-%m-%d')
                    except:
                        pass

                all_papers.append({
                    'title': title,
                    'arxiv_id': arxiv_id,
                    'link': link,
                    'abstract': content,
                    'source_name': src['name'],
                    'date': pub_date,
                })
                count += 1
            if count > 0:
                log(f"    [{src['name']}] ✓ {count} 篇")
            time.sleep(1)
        except Exception as e:
            log(f"    [{src['name']}] ✗ {e}")
            time.sleep(1)
    return all_papers


# ===================== ArXiv API 备选 =====================
def get_arxiv_papers_api(query="llm agent", max_results=5):
    log(f"  [备选] ArXiv API (query={query})...")
    encoded_q = urllib.parse.quote(f"all:{query}")
    url = f"https://export.arxiv.org/api/query?search_query={encoded_q}&sortBy=submittedDate&sortOrder=descending&max_results={max_results}"
    try:
        req = urllib.request.Request(url)
        req.add_header('User-Agent', 'Mozilla/5.0 ResearchBot/1.0')
        ctx = ssl.create_default_context()
        resp = urllib.request.urlopen(req, timeout=20, context=ctx)
        xml = resp.read().decode('utf-8')
        entries = re.findall(r'<entry>(.*?)</entry>', xml, re.DOTALL)
        papers = []
        for entry in entries:
            title_m = re.search(r'<title>(.*?)</title>', entry, re.DOTALL)
            id_m = re.search(r'<id>http://arxiv.org/abs/(.*?)(?:v\d+)?</id>', entry)
            summary_m = re.search(r'<summary>(.*?)</summary>', entry, re.DOTALL)
            if title_m and id_m:
                papers.append({
                    'title': title_m.group(1).strip().replace('\n', ' '),
                    'arxiv_id': id_m.group(1).strip(),
                    'link': f"https://arxiv.org/abs/{id_m.group(1).strip()}",
                    'abstract': summary_m.group(1).strip().replace('\n', ' ')[:1000] if summary_m else '',
                    'source_name': 'arXiv',
                })
        log(f"  [备选] ArXiv: ✓ {len(papers)} 篇")
        return papers
    except Exception as e:
        log(f"  [备选] ArXiv: ✗ {e}")
        return []


# ===================== HTML 邮件生成（3.26 样式） =====================
def generate_email_html(sections):
    now = datetime.now()
    weekdays = ['周一','周二','周三','周四','周五','周六','周日']
    today_cn = f"{now.year}年{now.month}月{now.day}日 {weekdays[now.weekday()]}"
    total = sum(len(s['papers']) for s in sections.values())

    # 统计
    stats_parts = []
    for sec in sections.values():
        stats_parts.append(f"{sec['config']['label']} {len(sec['papers'])}篇")

    html = f"""<!DOCTYPE html>
<html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"></head>
<body style="margin:0;padding:0;background-color:#EAEEF3;-webkit-font-smoothing:antialiased;">
<div style="background-color:#EAEEF3;padding:24px 12px;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display','Segoe UI',Helvetica,Arial,sans-serif;color:#2D3748;line-height:1.7;">
<div style="max-width:680px;margin:0 auto;">

<!-- ===== 品牌色条 ===== -->
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="border-radius:16px 16px 0 0;overflow:hidden;">
<tr>
<td style="background-color:#3182CE;height:4px;width:34%;" width="34%"></td>
<td style="background-color:#E53E3E;height:4px;width:33%;" width="33%"></td>
<td style="background-color:#38A169;height:4px;width:33%;" width="33%"></td>
</tr>
</table>

<!-- ===== HEADER ===== -->
<div style="background-color:#1A2332;padding:32px 32px 28px;">
<table width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
<td width="72" valign="top">
<div style="background:#FFFFFF;border-radius:16px;width:56px;height:56px;text-align:center;line-height:56px;">
<img src="https://raw.githubusercontent.com/AGI-FBHC/.github/main/profile/doc/image/gpt1trans.png" alt="AGI" style="width:40px;height:40px;display:inline-block;vertical-align:middle;">
</div>
</td>
<td valign="middle" style="padding-left:4px;">
<h1 style="margin:0;font-size:22px;color:#FFFFFF;font-weight:700;letter-spacing:0.3px;">AGI&amp;FBHC</h1>
<p style="margin:3px 0 0;font-size:13px;color:#8BA3C7;font-weight:400;">科研热点推送 · {today_cn}</p>
</td>
</tr></table>
</div>

<!-- ===== 数据概览 ===== -->
<div style="background-color:#1E2A3A;padding:14px 32px;border-bottom:1px solid rgba(255,255,255,0.06);">
<p style="margin:0;font-size:12px;color:#7B93AF;letter-spacing:0.3px;">
📊&nbsp; 今日收录 <span style="color:#FFFFFF;font-weight:600;">{total}</span> 篇&nbsp;&nbsp;│&nbsp;&nbsp;{'&nbsp;&nbsp;│&nbsp;&nbsp;'.join(stats_parts)}
</p>
</div>

<!-- ===== 正文区 ===== -->
<div style="background-color:#FFFFFF;padding:8px 0;">
"""

    section_idx = 0
    for key, sec in sections.items():
        cfg = sec['config']
        papers = sec['papers']
        if not papers:
            continue
        section_idx += 1

        # 方向间分隔线
        if section_idx > 1:
            html += '<div style="margin:8px 32px 0;border-top:1px solid #EDF2F7;"></div>\n'

        # 方向标题
        html += f"""<div style="padding:24px 32px 8px;">
<table width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
<td style="font-size:17px;color:#1A202C;font-weight:700;">
<span style="color:{cfg['color']};font-size:20px;vertical-align:middle;">●</span>&nbsp;&nbsp;{cfg['label']}
</td>
<td align="right">
<span style="font-size:11px;color:#A0AEC0;background:#F7FAFC;padding:4px 12px;border-radius:10px;">{len(papers)} 篇精选</span>
</td>
</tr></table>
</div>
"""

        for i, p in enumerate(papers, 1):
            keywords = p.get('llm_keywords', ['前沿研究'])
            summary = p.get('llm_summary', '')

            # 关键词
            kw_html = ''.join([
                f'<span style="display:inline-block;background:{cfg["kw_bg"]};color:{cfg["kw_color"]};padding:3px 10px;border-radius:4px;font-size:11px;font-weight:500;margin:0 6px 4px 0;letter-spacing:0.2px;">{k}</span>'
                for k in keywords
            ])

            # 来源渠道 + 链接
            source = p.get('source_name', '')
            if p.get('arxiv_id'):
                link_url = f"https://arxiv.org/abs/{p['arxiv_id']}"
                link_label = "arXiv"
            elif p.get('link'):
                link_url = p['link']
                link_label = source if source else "原文"
            else:
                link_url = "#"
                link_label = "N/A"

            # 卡片
            html += f"""<div style="margin:10px 24px;background:#FFFFFF;border:1px solid #EDF2F7;border-left:4px solid {cfg['color']};border-radius:4px 12px 12px 4px;padding:20px 24px;">

<!-- 编号 + 来源 -->
<table width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
<td>
<span style="display:inline-block;background:{cfg['color']};color:#FFFFFF;font-size:11px;font-weight:700;padding:2px 8px;border-radius:4px;margin-right:8px;">{i}</span>
<span style="font-size:11px;color:#A0AEC0;font-weight:500;">{source}</span>
</td>
<td align="right">
<a href="{link_url}" target="_blank" style="display:inline-block;font-size:11px;color:{cfg['link_color']};text-decoration:none;font-weight:600;padding:4px 12px;border:1px solid {cfg['color']}30;border-radius:6px;">{link_label}&nbsp;→</a>
</td>
</tr></table>

<!-- 标题 -->
<h3 style="margin:12px 0 14px;font-size:16px;color:#1A202C;font-weight:700;line-height:1.5;">{p['title']}</h3>

<!-- 核心看点 -->
<div style="padding:14px 16px;background:#F8FAFB;border-radius:8px;margin-bottom:14px;">
<p style="margin:0 0 6px;font-size:11px;color:{cfg['color']};font-weight:700;text-transform:uppercase;letter-spacing:0.8px;">💡 核心看点</p>
<p style="margin:0;font-size:14px;color:#4A5568;line-height:1.75;">{summary}</p>
</div>

<!-- 关键词 -->
<div>{kw_html}</div>

</div>
"""

    # ===== FOOTER =====
    now_str = now.strftime('%Y-%m-%d %H:%M')
    html += f"""</div>

<!-- FOOTER -->
<div style="background-color:#1A2332;padding:28px 32px;text-align:center;">
<p style="margin:0 0 4px;font-size:12px;color:#8BA3C7;">
由 <strong style="color:#63B3ED;">XClaw</strong> · AI 驱动 · 自动推送
</p>
<p style="margin:0 0 16px;font-size:11px;color:#4A6180;">
{now_str} · Nature · Science · Cell · NEJM · Lancet · arXiv
</p>
<div style="border-top:1px solid rgba(255,255,255,0.08);padding-top:14px;">
<a href="https://github.com/AGI-FBHC" style="color:#63B3ED;text-decoration:none;font-size:12px;font-weight:600;">GitHub</a>
<span style="color:#3D5068;margin:0 10px;">·</span>
<a href="mailto:agi-fbhc@outlook.com?subject=退订" style="color:#6B8299;text-decoration:none;font-size:12px;">退订</a>
<span style="color:#3D5068;margin:0 10px;">·</span>
<a href="mailto:agi-fbhc@outlook.com?subject=反馈" style="color:#6B8299;text-decoration:none;font-size:12px;">反馈</a>
</div>
</div>

<!-- 底部品牌色条 -->
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="border-radius:0 0 16px 16px;overflow:hidden;">
<tr>
<td style="background-color:#3182CE;height:3px;width:34%;" width="34%"></td>
<td style="background-color:#E53E3E;height:3px;width:33%;" width="33%"></td>
<td style="background-color:#38A169;height:3px;width:33%;" width="33%"></td>
</tr>
</table>

</div>
</div>
</body></html>"""
    return html


# ===================== 邮件发送（修改为逐个发送） =====================
def send_email_to_single_recipient(html_content, recipient, subject):
    """发送邮件给单个收件人"""
    payload = {
        "message": {
            "subject": subject,
            "body": {"contentType": "HTML", "content": html_content},
            "toRecipients": [{"emailAddress": {"address": recipient}}]
        }
    }
    data = json.dumps(payload, ensure_ascii=False).encode('utf-8')
    req = urllib.request.Request(
        'https://gateway.maton.ai/outlook/v1.0/me/sendMail',
        data=data, method='POST'
    )
    req.add_header('Authorization', f'Bearer {MATON_API_KEY}')
    req.add_header('Content-Type', 'application/json; charset=utf-8')
    ctx = ssl.create_default_context()
    resp = urllib.request.urlopen(req, timeout=30, context=ctx)
    return resp.status


def send_email_to_all(html_content, recipients, subject):
    """逐个发送邮件给所有收件人，每封间隔2秒"""
    success_count = 0
    failed_recipients = []
    
    log(f"  开始逐个发送，共 {len(recipients)} 人，间隔2秒...")
    
    for i, recipient in enumerate(recipients, 1):
        try:
            log(f"    [{i}/{len(recipients)}] 发送给 {recipient}...")
            status = send_email_to_single_recipient(html_content, recipient, subject)
            log(f"      ✓ 成功 (HTTP {status})")
            success_count += 1
        except Exception as e:
            log(f"      ✗ 失败: {e}")
            failed_recipients.append(recipient)
        
        # 每封邮件间隔2秒（最后一个不用等）
        if i < len(recipients):
            time.sleep(2)
    
    log(f"\n  发送完成: {success_count}/{len(recipients)} 成功")
    if failed_recipients:
        log(f"  失败收件人: {', '.join(failed_recipients)}")
    
    return success_count == len(recipients)


# ===================== 主流程 =====================
def main():
    log("=" * 55)
    log("📧 AGI&FBHC 科研热点推送 (3.26 样式)")
    log("   RSS多源获取 + 千问中文核心看点")
    log("   3 个方向 × 3 篇 = 9篇（全部中文）")
    log("=" * 55)
    log(f"收件人: {len(RECIPIENTS)} 人")
    log("")

    PAPERS_PER_DIRECTION = 3

    # 加载已推送记录（去重，保留30天）
    sent_history = load_sent_history()
    log(f"已推送记录: {len(sent_history)} 篇（30天内）")

    # ---- Step 1: 获取候选论文池 ----
    log("[1/2] 获取候选论文 + 千问生成中文核心看点...")
    sections = {}

    for key, feed_cfg in FEEDS.items():
        log(f"\n  📂 {feed_cfg['label']}:")
        candidates = fetch_rss_papers(feed_cfg['sources'], max_per_source=5)

        if not candidates and key == 'ai':
            time.sleep(3)
            candidates = get_arxiv_papers_api("llm agent OR multi-agent", 10)

        # 按顶刊优先 + 日期新优先排序
        candidates.sort(key=lambda p: (
            source_priority(p.get('source_name', '')),
            -(int(p['date'].replace('-', '')) if p.get('date') else 0)
        ))
        log(f"  候选池: {len(candidates)} 篇（已按顶刊+日期排序）")

        # ---- 逐篇调千问，成功才入选，同渠道不重复 ----
        selected = []
        used_channels = set()
        direction_hint = feed_cfg['label']
        for i, p in enumerate(candidates):
            if len(selected) >= PAPERS_PER_DIRECTION:
                break

            # 渠道去重
            channel = get_channel(p.get('source_name', ''))
            if channel in used_channels:
                continue

            # 已推送去重（每日不重复）
            if is_paper_sent(p['title'], sent_history):
                continue

            title_short = p['title'][:50] + ('...' if len(p['title']) > 50 else '')
            src_name = p.get('source_name', '?')
            log(f"    [{len(selected)+1}/{PAPERS_PER_DIRECTION}] [{src_name}] {title_short}")

            result = llm_generate(p['title'], p.get('abstract', ''), direction_hint)
            if result:
                p['llm_keywords'] = result['keywords']
                p['llm_summary'] = result['summary']
                selected.append(p)
                used_channels.add(channel)
                log(f"      ✓ 关键词: {', '.join(result['keywords'])}")
            else:
                log(f"      ✗ LLM失败，跳过换下一篇")

            time.sleep(1)  # 请求间隔

        sections[key] = {'config': feed_cfg, 'papers': selected}
        log(f"  → {feed_cfg['label']}: 入选 {len(selected)}/{PAPERS_PER_DIRECTION} 篇（全部中文核心看点）")

    total = sum(len(s['papers']) for s in sections.values())
    log(f"\n  📊 总计入选: {total} 篇（全部有中文核心看点）")

    if total == 0:
        log("❌ 没有获取到任何论文！退出")
        return 1

    # 打印最终入选论文
    log("\n  --- 最终入选 ---")
    for key, sec in sections.items():
        for p in sec['papers']:
            title = p['title'][:60] + ('...' if len(p['title']) > 60 else '')
            log(f"  {sec['config']['label'][:2]} | {title}")
            log(f"       关键词: {', '.join(p['llm_keywords'])}")

    # ---- Step 2: 生成 HTML + 逐个发送 ----
    log(f"\n[2/2] 生成邮件并逐个发送...")
    html = generate_email_html(sections)
    log(f"  HTML 大小: {len(html):,} 字符")

    preview_path = '/tmp/research_email_preview.html'
    with open(preview_path, 'w', encoding='utf-8') as f:
        f.write(html)
    log(f"  预览已保存: {preview_path}")

    today_short = datetime.now().strftime('%m/%d')
    subject = f"[AGI&FBHC科研热点推送] 学术前沿进展 · {today_short}"
    log(f"  收件人: {len(RECIPIENTS)} 人")
    log(f"  主题: {subject}")

    # 逐个发送邮件，每封间隔2秒
    all_success = send_email_to_all(html, RECIPIENTS, subject)
    
    if all_success:
        log(f"\n✅ 所有邮件发送成功！")
        log(f"  论文数: {total} 篇 (全部中文核心看点)")
        # 标记已推送，下次不再重复
        for sec in sections.values():
            for p in sec['papers']:
                mark_paper_sent(p['title'], sent_history)
        save_sent_history(sent_history)
        log(f"  已更新去重记录 ({len(sent_history)} 篇)")
        return 0
    else:
        log(f"\n⚠️ 部分邮件发送失败，请检查日志")
        return 1


if __name__ == "__main__":
    sys.exit(main())
