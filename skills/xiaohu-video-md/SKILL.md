---
name: 视频转写
description: "视频转写与翻译工具：抓取字幕/音频转写 → 输出 Markdown 文档；翻译视频 → 转写+翻译+烧录中文字幕。支持精确/快速两种转写模式。当用户说'视频转写''转写视频''翻译视频''视频转文字''配字幕''加字幕''视频转markdown'时必须执行完整翻译管线（提取音频→Whisper转写SRT→调用subtitle-polish翻译→烧录字幕到视频），不能只输出文档。"
---

# 视频转写工具

## 适用/能力
- **转写出文档**：抓取字幕或音频转写 → 输出 Markdown 文档（有字幕优先）。
- **翻译视频**：转写 → 翻译 → 烧录中文字幕 → 输出带字幕的视频文件。
- 支持精确模式（默认，large-v3-turbo，95% 精度）和快速模式（medium，90% 精度，快 81%）。
- **双版本输出**：中文内容生成中文版，非中文内容生成原文版 + 中文翻译版。

### 意图识别（必须严格遵守）
- 用户说"转写""转文字""出文档" → 只生成 Markdown 文档
- 用户说"翻译""翻译视频""配字幕""加字幕" → **必须执行完整的翻译视频管线**（提取音频 → Whisper 生成 SRT → 调用 subtitle-polish 翻译 → 烧录字幕到视频 → 同时生成 Markdown 文档），**不能只输出文档就结束**
- 输入是 URL → 先下载再处理
- 输入是本地文件路径 → 直接处理

### 字幕类型（翻译管线必须先确认）
- **中文字幕**：只显示中文翻译
- **中英双语字幕**：中文在上，英文在下

**翻译视频时，除非用户在对话中明确指定了字幕类型（说了"中文""双语""中英"等），否则必须用 AskUserQuestion 弹选项让用户选择。** ARGUMENTS 里的字幕类型不算用户指定。示例：
```
AskUserQuestion(
  question="选择字幕类型",
  options=["中文字幕（只显示中文）", "中英双语字幕（中文在上，英文在下）"]
)
```

双语字幕 SRT 格式（每条两行）：
```
1
00:00:03,660 --> 00:00:06,360
中文翻译在上面
English original below
```

**双语烧录走 ASS，不走 `subtitles` + force_style**（中文大 / 英文小，形成反差）：
- subtitle-polish 翻译产出「双语 SRT」（中文在上、英文在下，时间戳一句对一句）后，调脚本转双语 ASS：
  ```bash
  python3 ~/.claude/skills/xiaohu-subtitle-polish/scripts/bilingual_ass.py \
    <双语SRT> --output <双语ASS> [--cn-size N] [--height 视频高度]
  ```
- 再用 `ass=<双语ASS>` 滤镜烧录（不是 `subtitles=`）。完整规则见 `xiaohu-subtitle-polish` SKILL.md「双语字幕模式」段。
- 字号：用户给了中文字号就传 `--cn-size`，英文自动按 中文 / 1.7 算；没给则脚本按分辨率选默认。中文︰英文 ≈ 1.7 是实测干净反差。

⛔ **为什么不用 subtitles force_style 做双语**：force_style 的 FontSize 对整条统一，做不到一条内中文大英文小；SRT 里的 inline `{\fsN}` 会被 ffmpeg 剥离（2026-05-31 实测三档字号 md5 全同）。只有 ASS 喂 libass 才能一条内分字号。
⛔ **ASS FontSize 是相对值不是像素**：libass 已按视频分辨率自动缩放，不要按分辨率线性放大（1080p 的 17 乘 2 变 34 会让 4K 字幕占满下半屏）。2026-05-26 Jony Ive 法拉利视频踩坑根治。

## 强制规则（先读配置再执行）
- 执行任何命令/写入任何文件前，必须先读取本技能目录 `config.json`，取 `output_dir` 作为 `<输出根>`（支持 `~` 展开）。
- 文档中的所有 `<输出根>/...` 在执行前必须替换为真实绝对路径；禁止把 `<输出根>` 原样带到命令里执行（否则会写到当前目录，表现为“乱保存”）。
- 若 `config.json` 缺失、`output_dir` 为空/相对路径/不可写：立即停止并提示用户在网页面板填写，或用 `--outdir <绝对路径>` 覆盖。
- 只有当用户明确给出“绝对路径输出位置”并确认时，才允许写入用户指定路径；否则默认只写 `<输出根>/tmp/` 与 `<输出根>/data/`。

**建议的“输出根解析”固定前置步骤（避免手打长路径导致误写目录）**：
```bash
# 在本技能目录执行
OUTPUT_ROOT="$(python3 - <<'PY'
import json, os
from pathlib import Path

cfg = json.load(open("config.json", "r", encoding="utf-8"))
out = Path(os.path.expanduser(str(cfg.get("output_dir", ""))).strip())
if not out.is_absolute():
    raise SystemExit("config.json: output_dir 必须是绝对路径或以 ~ 开头")
print(str(out))
PY
)"
mkdir -p "$OUTPUT_ROOT/tmp" "$OUTPUT_ROOT/data"
echo "OUTPUT_ROOT=$OUTPUT_ROOT"
```
后续所有命令都必须使用 `$OUTPUT_ROOT/...`，不要在命令里手写/粘贴完整长路径。

## 通用配置

**路径说明**：
- **脚本目录**：`scripts/`
- **输出根需显式配置**：在本技能目录下 `config.json` 设置 `output_dir=<绝对路径>`，或调用时用 `--outdir <绝对路径>`（命令行优先）。必须是绝对路径；`output_dir` 为空/缺失/相对路径时，脚本会强制提示用户输入绝对路径并写回 `config.json`，不会默认回落技能目录。根目录下自动创建/使用 `tmp/`（中间产物）和 `data/`（最终产物）。

**转写引擎**（默认走脚本，零配置开箱即用）：
- **默认：MLX Whisper / faster-whisper**（`scripts/transcribe_srt.py`）——首次运行自动从 HuggingFace 下载模型，无需手动准备。所有场景一律首选脚本。
- **可选备份：whisper-cli**（whisper-cpp）——仅当用户明确指定、或上面两个都装不了时才用。需自行 `brew install whisper-cpp` 并把 ggml 模型下到 `~/.cache/whisper-cpp/`（见 `初始化.md`）：
  - 精确模式：`~/.cache/whisper-cpp/ggml-large-v3-turbo.bin`（默认模型）
  - 快速模式：`~/.cache/whisper-cpp/ggml-medium.bin`（用户没有要求不允许使用此模型）

## 输出路径选择逻辑
- 步骤0：先解析输出根（命令行 `--outdir` → `config.json`），`output_dir` 缺失/无效时立即提示用户输入绝对路径并写回 `config.json`，未配置不可继续。
- 默认将结果写入 `<输出根>/data/`，不再询问；用户指令/工作流若明确指定路径，优先使用指定路径（必须是绝对路径）。

## 转写方案选择逻辑（按场景和时长）

### 烧字幕场景（需要精确时间戳）

根据音频时长选择方案：

| 音频时长 | 方案 | 原因 |
|----------|------|------|
| <2 分钟 | **faster-whisper** | word-level 精度最高，CPU 几秒完成 |
| ≥2 分钟 | **MLX Whisper** | word-level + Metal GPU，速度和精度兼得 |

**faster-whisper 命令**（<2分钟短视频）：
```bash
python3 scripts/transcribe_srt.py "<输入文件>" --output "<输出文件>.srt"
```

**MLX Whisper 命令**（≥2分钟，翻译管线默认）— 一律走脚本，不在对话里现写 Python：
```bash
python3 scripts/transcribe_srt.py "<输入文件>" --output "<输出文件>.srt"
# 语种误判时加 --language en
```
脚本默认按 Whisper segment 边界切（不是按字符 greedy 切），下游字幕不会出现夹生帧。

**禁止在烧字幕场景使用 whisper-cli**：没有 word-level timestamps，字幕会明显不同步。

### 只出文档场景（不需要精确时间戳）

默认同样走脚本（自动下模型、零配置），转写后从 SRT 取纯文本（去掉序号和时间戳行）即可：
```bash
python3 scripts/transcribe_srt.py "<输入文件>" --output "<输出文件>.srt"
```
> 可选备份：若已装 whisper-cpp 且想要最快的纯文本输出，可用 whisper-cli（需自备 ggml 模型，见上方「转写引擎」）：
> ```bash
> whisper-cli -m ~/.cache/whisper-cpp/ggml-large-v3-turbo.bin -t 8 <输入文件> -otxt
> # 快速模式（用户说"快速"/"快"）：把模型换成 ggml-medium.bin
> ```

### 长视频特殊处理（>10分钟）

- 字幕翻译必须**分段并行**：每段约 500 条，用并行 Agent 翻译，翻译完合并重新编号
- YouTube 视频下载**不要用 `--download-sections`**（会先下完整视频再裁剪，极慢），直接下完整视频后用 ffmpeg `-ss` 裁剪
- 下载分辨率一步到位选 1080p，优先 AV1 格式（体积最小）

## 通用 Markdown 生成规则（适用于所有场景）
- 读取指定文本（清洗后的字幕 `cleaned.txt` 或 Whisper 输出 txt），严禁增删改原文，只做标点、合句、分段。
- 判定语言：
  - **中文**：合并短句、规范标点、按语义分段，输出 1 个文件：`<输出根>/data/<视频标题>-中文.md`。
  - **非中文**：先按原文语言生成 `<输出根>/data/<视频标题>-原文.md`（同样不得增删改），再按 `非中文翻译规则.md` 翻译该原文生成 `<输出根>/data/<视频标题>-中文.md`。
- 元信息 front matter：`title`、`source_url`。
- 必须覆盖全部文本内容，不得遗漏。

## 使用指导

### 抓取字幕（仅限出文档场景）

**使用场景**：**只出文档**时，视频有字幕则优先抓取字幕（比 Whisper 快）。
**⛔ 烧字幕场景禁止使用本流程**：YouTube 自动字幕是滚动叠加格式，无法提取干净的逐句文本+精确时间戳。烧字幕必须走"翻译视频管线"用 Whisper 转写。

**处理流程**：

1) 先确保输出根有效（步骤0 已完成）。

2) 仅抓字幕（不下载视频）：
```bash
# 下载 .vtt 字幕（最快）
yt-dlp --skip-download --write-subs --write-auto-subs \
  --sub-lang "zh-Hans,zh-CN,en" \
  -o "<输出根>/tmp/%(id)s.%(ext)s" \
  "<视频URL>"
```
- 优先下载 .vtt 格式（最快，无需转换）。
- **兜底机制**：如果字幕下载失败，自动切换到"无字幕兜底（音频转写）"流程
- YouTube 若缺字幕/需 PO token：**推荐直接用脚本自动重试并从浏览器读取 cookies**：
```bash
python3 scripts/youtube_subs_download.py "<视频URL>"
```
  - 首次尝试无 cookies（更快）；失败后自动 `--cookies-from-browser chrome` 重试。
  - 常用浏览器非 Chrome：`python3 scripts/youtube_subs_download.py --browser firefox "<视频URL>"`
  - 仍失败（PO token / 更强风控）：再提示用户提供 `--extractor-args "youtube:po_token=..."` 或切换代理后重试。

2) 使用脚本清洗字幕（**减少 50% tokens 消耗**）：
```bash
# 清洗 vtt/srt → 纯文本（每行一句）
# <id>.zh-Hans.vtt 为 yt-dlp 实际输出的字幕文件名（语言代码可能是 zh-Hans、zh-CN 等）
scripts/vtt_to_text.sh "<输出根>/tmp/<id>.<语言代码>.vtt" > "<输出根>/tmp/cleaned.txt"
```

3) AI 读取清洗后的文本并生成 Markdown：
- 读取 `<输出根>/tmp/cleaned.txt` 全部内容，按“通用 Markdown 生成规则”产出。

### 无字幕兜底（音频转写）

**使用场景**：当视频没有字幕时，自动提取音频并用 Whisper 转写。

**处理流程**：

1) 提取音频（截断标题并去符号，文件名更短）：
```bash
yt-dlp -x --audio-format mp3 --embed-thumbnail --add-metadata \
  --restrict-filenames \
  -o "<输出根>/tmp/%(title).40s.%(ext)s" \
  "<视频URL>"
```
 - YouTube 若遇 403/SABR：**推荐用脚本失败自动读取浏览器 cookies 重试**：
```bash
python3 scripts/youtube_audio_download.py "<视频URL>"
```

2) Whisper 转写（默认走脚本，自动下模型；不指定语言让其自动检测中/英/日等）：
```bash
python3 scripts/transcribe_srt.py "<输出根>/tmp/<audio>.mp3" --output "<输出根>/tmp/<audio>.srt"
```
> 可选备份：已装 whisper-cpp 时可用 whisper-cli 直接出 txt（需自备 ggml 模型，见上方「转写引擎」）：
> ```bash
> whisper-cli -m ~/.cache/whisper-cpp/ggml-large-v3-turbo.bin -t 8 "<输出根>/tmp/<audio>.mp3" -otxt
> ```

3) AI 读取转写文本并生成 Markdown：
- 读取 `<输出根>/tmp/<audio>.srt`（默认脚本路线）或 `<audio>.mp3.txt`（whisper-cli 路线），去掉序号和时间戳行得到纯文本，按“通用 Markdown 生成规则”产出（`<audio>` 即视频ID）。

### 抖音视频处理

**重要原则**：
- **不要预先检查**依赖和登录状态，直接执行主流程
- **遇到错误时再检查**，这样可以节省时间并提高效率
- 信任环境配置，假设依赖和登录状态正常
- **输出根目录为必填**：需在本技能目录 `config.json` 设置 `output_dir`（绝对路径），或调用时使用 `--outdir <绝对路径>`（命令行优先）。缺失/无效时脚本会提示用户输入绝对路径并写回 `config.json`。根目录下使用 `tmp/`、`data/`。
- 抓取使用可见浏览器（非 headless）以获取 aweme detail，脚本会将链接标准化为 `https://www.douyin.com/video/<ID>`。

**链接格式转换**（脚本自动处理）：短链需先跳转取完整 URL；`modal_id` 取 ID 后拼 `/video/ID`；标准 `/video/<ID>` 可直接使用。

**处理流程**：
1) 下载音频：
```bash
python3 scripts/douyin_download.py <抖音视频URL> --audio
```
输出：`<输出根>/tmp/<视频标题>-音频.m4a`

2) 转换音频格式：
```bash
ffmpeg -i "<输出根>/tmp/<视频标题>-音频.m4a" -acodec libmp3lame -q:a 2 "<输出根>/tmp/<视频标题>-音频.mp3"
```

3) Whisper 转写（默认走脚本，自动下模型）：
```bash
python3 scripts/transcribe_srt.py "<输出根>/tmp/<视频标题>-音频.mp3" --output "<输出根>/tmp/<视频标题>-音频.srt" --language zh
```
（其他语言可改 `--language en/ja/...`；可选备份引擎 whisper-cli 见上方「转写引擎」）

4) 生成 Markdown：
   - 读取 `<输出根>/tmp/<视频标题>-音频.srt`，去掉序号和时间戳行得到纯文本，按“通用 Markdown 生成规则”产出（默认中文）。

**错误处理**：
- **步骤1失败（下载音频）**：
  - 如果报错 `ModuleNotFoundError: No module named 'patchright'`，读取 `抖音初始化.md` 安装依赖
  - 如果报错 `未检测到浏览器登录状态`，运行 `python3 scripts/douyin_login.py` 进行登录
  - 其他错误 → 读取 `抖音初始化.md` 查看技术细节和解决方案
- **其他步骤失败** → 读取 `抖音初始化.md` 查看技术细节和解决方案

### 翻译视频管线（完整流程）

**触发条件**：用户说"翻译视频""翻译该视频""配字幕""加字幕"等——最终目标 = 输出一个带中文字幕的视频文件（同时生成 Markdown 文档）。

**⛔ 铁律：翻译管线的英文 SRT 只能由 Whisper 转写生成，禁止使用 YouTube 自动字幕（yt-dlp --write-auto-subs）。**
原因：YouTube 自动字幕是滚动叠加格式（每条包含前一条文本），无法提取干净逐句文本+精确时间戳，导致烧录后字幕不同步。Whisper word-level timestamps 是唯一可靠的时间源。

**输入判断**：
- URL → 先用 yt-dlp / douyin_download 下载**视频文件**到 `<输出根>/tmp/`（只下视频，不抓字幕）
- 本地文件路径 → 直接使用

**管线步骤**：

#### 步骤 0：确认字幕类型（⛔ 门控，必须在任何其他步骤之前执行）

用户在对话中明确指定了字幕类型（说了"中文""双语""中英""bilingual"等）→ 按用户指定的类型执行。
**其他所有情况 → 必须用 AskUserQuestion 弹选项**：
```
AskUserQuestion(
  question="选择字幕类型",
  options=["中文字幕（只显示中文）", "中英双语字幕（中文在上，英文在下）"]
)
```
**⛔ 禁止绕过**：ARGUMENTS 里的字幕类型不算用户指定——只有用户在对话中亲自说的才算。不弹选项就开始步骤1 = 流程错误。config.json 的 `subtitle_type` 只是默认值，不能替代用户确认。

#### 步骤 1：提取音频
```bash
ffmpeg -i "<视频文件>" -vn -acodec libmp3lame -q:a 2 "<输出根>/tmp/<文件名>.mp3"
```

#### 步骤 2：精确转写生成原文 SRT（按时长选方案）

**短视频（<2分钟）→ faster-whisper**：
```bash
python3 scripts/transcribe_srt.py "<输出根>/tmp/<文件名>.mp3" \
  --output "<输出根>/tmp/<文件名>.srt"
```

**长视频（≥2分钟）→ MLX Whisper**（默认，仍走脚本）：
```bash
python3 scripts/transcribe_srt.py "<输出根>/tmp/<文件名>.mp3" \
  --output "<输出根>/tmp/<文件名>.srt"
```

**多语言混轨/语种误判 → 加 `--language en`**（强制重转）：
```bash
python3 scripts/transcribe_srt.py "<输出根>/tmp/<文件名>.mp3" \
  --output "<输出根>/tmp/<文件名>.srt" \
  --language en
```

⛔ **任何情况下不要在对话里现写 mlx_whisper Python 代码**——脚本已经按 Whisper segment 切（merge_words_to_segments 函数：segment 作基础 / 超 6s 才按词拆 / <500ms 才合并），绕开脚本自己写 `MAX_CHARS=50` greedy 会把 A 句尾巴+B 句开头挤进同一帧（2026-05-28 ElevenLabs 踩坑根治）。

脚本特性：
- MLX Whisper Metal GPU 加速，word-level timestamps 精度最高（140 分钟音频约 5-8 分钟完成）
- `--language` 支持强制语种（en/zh/ja 等），不传则自动检测
- `--max-line-ms` 控制单条最大时长（默认 6000ms）
- MLX 不可用自动降级 faster-whisper

**兜底**：若 MLX Whisper 未安装（`pip3 install --break-system-packages mlx-whisper`），用 faster-whisper。若 faster-whisper 也不可用，最后用 whisper-cli `-ml 50`（精度最低，仅应急）。

输出：`<输出根>/tmp/<文件名>.srt`（原文 SRT，word-level 精确时间戳）

#### 步骤 3：调用 `xiaohu-subtitle-polish` 技能翻译润色
**使用 Skill 工具调用**，传入原文 SRT 路径：
```
# 中文单语
/xiaohu-subtitle-polish <输出根>/tmp/<文件名>.srt --output <输出根>/tmp/<文件名>-zh.srt
# 中英双语（步骤 0 用户选了双语时）
/xiaohu-subtitle-polish <输出根>/tmp/<文件名>.srt --output <输出根>/tmp/<文件名>-zh.srt --bilingual
```
- subtitle-polish 负责**全部**字幕工作：翻译、去标点、断句（≤18字/行）、时间戳对齐、去冗余、专有名词处理
- **双语模式**：subtitle-polish 产出「双语 SRT」（中文在上、英文在下，时间戳一句对一句），具体见其 SKILL.md「双语字幕模式」段
- video-md **不做任何字幕翻译和润色**，全部交给 subtitle-polish
- 输出：润色后的中文 SRT（单语）或双语 SRT（双语）

**⛔ subtitle-polish Skill 返回后，立即执行步骤 4（烧录）。不输出任何中间报告，不等用户确认。subtitle-polish 有自己的输出报告步骤，在管线中忽略它，直接继续。**

#### 步骤 4：烧录字幕 + 水印（默认带水印）

**默认行为**：从 `config.json` 的 `settings` 读取水印配置（`watermark_enabled`、`watermark_text` 等）。默认开启水印，用户说"不要水印""去掉水印"时关闭。

字幕 + 水印必须在同一条 ffmpeg 命令中完成（一次编码，避免画质损失）。

**双语先转 ASS 再烧**：双语模式下，先把双语 SRT 转成双语 ASS（中文大 / 英文小），烧录时用 `ass=<双语ASS>` 替代下面命令里的 `subtitles=<SRT>:force_style=...`，其余（水印 drawtext、`-c:a aac`）不变：
```bash
python3 ~/.claude/skills/xiaohu-subtitle-polish/scripts/bilingual_ass.py \
  <输出根>/tmp/<文件名>-zh.srt --output <输出根>/tmp/<文件名>-zh.ass [--cn-size N] [--height 高度]
# 烧录：-vf "ass=<输出根>/tmp/<文件名>-zh.ass,drawtext=...水印..."
```
中文单语仍按下面的 `subtitles=` + force_style 烧。

**音频编码强制 AAC**：yt-dlp 下载的音频经常是 Opus 编码，X/微信等平台不支持。烧录时必须用 `-c:a aac -b:a 128k`，**禁止用 `-c:a copy`**（2026-03-17 踩坑：Opus 音频导致 X 上传失败）。

**原视频有硬字幕时的避让**：如果原视频底部已有烧录过的字幕（如英文原字幕），新字幕需上移避让，不能遮挡原字幕。按分辨率选参数（详见 `xiaohu-subtitle-polish` SKILL.md 烧录段）：
- **720p 单行硬字幕**：`MarginV=42, FontSize=18`
- **1080p 单行硬字幕**：`MarginV=42, FontSize=19`
- **1080p 两行硬字幕**（动态变行也按此值）：`MarginV=60, FontSize=19`
- **4K 单行硬字幕**：`MarginV=42, FontSize=19`

⚠️ **MarginV 单位不是像素**——它相对 ASS 默认 PlayResY=288。在 1080p 视频里 MarginV=N 实际渲染高度 ≈ N × 3.75 px from bottom。所以 MarginV=110 → 412px ≈ 画面正中（不是 110px 距底），别按像素直觉调（2026-05-29 陶哲轩视频踩坑根治：我之前按像素直觉设 110 把中文推到画面正中）。

**原英文动态变行**（一句 1 行一句 2 行）：用避两行的 MarginV=60，1 行段中文显得稍高一点点是可接受代价（远好过中文挤进 2 行英文中间）。

烧录后**必须抽 ≥2 帧验证**——选原英文是 1 行的一帧 + 是 2 行的一帧，两帧都不遮挡才算过。只看一帧就交付 = 文档已警告过的踩坑。

**无水印烧录**（仅用户明确说"不要水印"时）：
```bash
ffmpeg -y -i "<视频文件>" \
  -vf "subtitles=<输出根>/tmp/<文件名>-zh.srt:force_style='FontName=PingFang SC,Bold=1,FontSize=20,PrimaryColour=&H00FFFFFF,OutlineColour=&H40000000,Outline=1,Shadow=0,MarginV=30'" \
  -c:a aac -b:a 128k ~/Downloads/<视频标题>-中文字幕.mp4
```

**带水印烧录**（默认）：

> **macOS drawtext 中文字体问题（重要）**：
> ffmpeg 的 `drawtext` 滤镜使用 fontconfig 查找字体，但 macOS 的 fontconfig **无法索引苹方**，会回退到 Verdana（不支持中文）→ 中文显示为方块。
> **必须使用 `fontfile=` 指定字体文件绝对路径**，禁止使用 `font=` 名称查找。
> 注意：`subtitles` 滤镜用 CoreText 不受此影响，只有 `drawtext` 需要 `fontfile`。
> **水印字体用圆体（Yuanti SC）**，比苹方更好看，且 index 0 就是 SC 简体，不会出现方块问题。PingFang.ttc 的 index 0 是 HK 变体，简体字符显示为方块。

```bash
# 1. 解析水印中文字体路径（圆体 Yuanti SC，index 0 = SC 简体）
FONT=$(find /System/Library/AssetsV2 -name "Yuanti.ttc" 2>/dev/null | head -1)
[ -z "$FONT" ] && FONT=$(find /System/Library/AssetsV2 -name "PingFang.ttc" 2>/dev/null | head -1)
[ -z "$FONT" ] && FONT="/System/Library/Fonts/STHeiti Medium.ttc"

# 2. 字幕 + 间歇水印一次烧录
# 水印默认参数：透明度 28%、每次 4 秒、0.5 秒渐隐渐出、左上角、出现 3 次
# 时间点均匀分布（示例：8s/38s/72s，根据视频时长调整）
ffmpeg -y -i "<视频文件>" \
  -vf "subtitles=<SRT路径>:force_style='FontName=PingFang SC,Bold=1,FontSize=20,PrimaryColour=&H00FFFFFF,OutlineColour=&H40000000,Outline=1,Shadow=0,MarginV=30',\
drawtext=text='<水印文字>':fontfile=${FONT}:fontsize=44:fontcolor=white:alpha='0.28*min(min((t-T1)/0.5,1),(T1+4-t)/0.5)':x=40:y=35:enable='between(t,T1,T1+4)',\
drawtext=text='<水印文字>':fontfile=${FONT}:fontsize=44:fontcolor=white:alpha='0.28*min(min((t-T2)/0.5,1),(T2+4-t)/0.5)':x=40:y=35:enable='between(t,T2,T2+4)',\
drawtext=text='<水印文字>':fontfile=${FONT}:fontsize=44:fontcolor=white:alpha='0.28*min(min((t-T3)/0.5,1),(T3+4-t)/0.5)':x=40:y=35:enable='between(t,T3,T3+4)'" \
  -c:a aac -b:a 128k ~/Downloads/<视频标题>-中文字幕.mp4
```

**水印参数说明**：
| 参数 | 默认值 | 说明 |
|------|--------|------|
| 透明度 | 0.28（28%） | 淡而可见，不干扰观看 |
| 渐隐渐出 | 0.5 秒 | 自然过渡，不突兀 |
| 每次持续 | 见下方规则 | 按视频时长调整 |
| 最少次数 | 3 次 | 开头、中间、结尾必须各有一次 |
| 位置 | 左上角 (x=40, y=35) | 不遮挡字幕 |
| 字号 | 44 | 4K 视频下小巧；1080p 可降至 24-28 |

水印参数从 `config.json` 的 `settings` 读取，用户可在配置面板修改。命令行/对话中指定的参数优先于配置文件。

**水印次数和持续时间计算规则**（按视频时长动态调整）：

| 视频时长 | 水印次数 | 每次持续 |
|----------|----------|----------|
| <5 分钟 | 3 次 | 4 秒 |
| 5-30 分钟 | 3 次 | 4 秒 |
| 30-60 分钟 | 5 次 | 5 秒 |
| >60 分钟 | 每 15 分钟 1 次（最少 5 次） | 10 秒 |

**时间点分布规则**：
- 第 1 次固定在开头（约 8-15 秒处）
- 最后 1 次固定在结尾前（结尾前 15-30 秒）
- 中间的次数在首尾之间均匀分布
- 例：140 分钟视频 → 9 次（每 15 分钟），T=15s/900s/1800s/2700s/3600s/4500s/5400s/6300s/8400s

输出保存到 `~/Downloads/`。

#### 步骤 5：生成 Markdown 文档（与字幕管线并行）
- 同时用 `-otxt` 模式获取纯文本，或直接读取 SRT 内容
- 按"通用 Markdown 生成规则"生成文档（非中文 → 原文版 + 中文版）

**核心原则**：
- 字幕翻译润色的**所有规则**由 `xiaohu-subtitle-polish` 技能定义和执行，video-md **不重复定义、不自行实现**
- video-md 的职责 = 音频提取 + Whisper 转写 + 编排管线 + Markdown 生成
- 这是管线编排（orchestration），不是规则复制（duplication）
- **⛔ 管线不停顿**：subtitle-polish 返回后必须直接继续烧录步骤（步骤 4），不得停下来报告中间结果等用户确认。整条管线只在最终产物（视频文件 + Markdown）全部完成后报告一次

## Markdown 清洗要点

遵循“通用 Markdown 生成规则”：严禁增删改原文，仅做标点/分段/合并短句，front matter 仅含 `title`、`source_url`。

## 依赖

**所需依赖**：
- 工具：`yt-dlp`、`ffmpeg`；`whisper-cpp`（可选备份转写引擎，不装也能用）
- Python 包：`mlx-whisper`（Apple 芯片首选）或 `faster-whisper`（通用首选）、`patchright`（抖音视频处理必需）
- 脚本：`scripts/transcribe_srt.py`、`scripts/vtt_to_text.sh`、`scripts/douyin_login.py`、`scripts/douyin_download.py`
- 模型：mlx-whisper / faster-whisper 首次运行自动从 HuggingFace 下载，无需手动准备；whisper-cpp 备份引擎需自行把 `ggml-large-v3-turbo.bin`、`ggml-medium.bin` 下到 `~/.cache/whisper-cpp/`

**依赖检查原则**：
- 直接执行主流程，遇错再查 `初始化.md` / `抖音初始化.md` 补依赖，默认假设环境已装好

**当遇到依赖相关错误时**：
- 读取相应的初始化文档并按指引自动安装
- 常规初始化：`初始化.md`
- 抖音初始化：`抖音初始化.md`
- 安装完成后返回主流程继续执行用户请求

## 临时文件处理

**临时文件位置**：`<输出根>/tmp/`

**临时文件类型**：
- 字幕文件（.vtt, .srt）
- Whisper 转写输出的文本文件（.mp3.txt）
- 清洗后的字幕文本文件（cleaned.txt，仅字幕抓取时使用）

**清理策略**：
- AI 处理完成后，可清理临时字幕文件
- Whisper 转写结果文件可保留用于调试
- 用户可随时手动清理 `<输出根>/tmp/` 目录
- **重要**：最终输出文件（.md）保存在 `<输出根>/data/`，不受影响

## 错误处理

**常见错误及处理方法**：

1. **字幕下载失败**：
   - **原因**：视频无字幕、地区限制、需要 PO token
   - **处理**：提示用户提供 cookies（`--cookies-from-browser chrome`）或切换代理
   - **兜底**：自动切换到音频转写流程

2. **Whisper 转写失败**：
   - **原因**：模型文件缺失、音频格式不支持
   - **处理**：检查模型是否已下载，尝试转换音频格式

3. **磁盘空间不足**：
   - **原因**：临时文件或输出文件占用空间过大
   - **处理**：清理 `<输出根>/tmp/` 临时文件目录

# 翻译规则文档

- 非中文内容翻译时，按需读取 `非中文翻译规则.md` 并遵守其中规则。
- 中文内容严禁使用翻译规则；仅做标点、分段、合并短句，不得增删改原文。
