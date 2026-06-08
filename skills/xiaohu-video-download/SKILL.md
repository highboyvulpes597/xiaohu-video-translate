---
name: 下载视频
description: "视频下载工具：下载视频和外挂字幕文件、仅下载音频、批量下载播放列表、为本地视频烧录中文字幕。支持字幕翻译功能。当用户说'下载视频''下载这个视频''下载音频''下载播放列表''yt-dlp''烧录''烧字幕''重新烧录''烧录字幕'时使用。"
---

# 视频下载工具

## 适用/能力
- 下载整段视频（获取素材）：下载视频文件和外挂中文字幕，无字幕则仅下载视频。
- 下载播放列表：批量下载多个视频，支持指定范围或全部。
- 仅下载音频：提取音频并嵌入封面和元数据。
- **为本地视频添加字幕**：从本地视频提取音频 → Whisper 转写 → 翻译成中文 → **烧录字幕到视频画面**。

## 强制规则（先读配置再执行）
- 执行任何命令/写入任何文件前，必须先读取本技能目录 `config.json`，取 `output_dir` 作为 `<输出根>`（支持 `~` 展开）。
- 文档中的所有 `<输出根>/...` 在执行前必须替换为真实绝对路径；禁止把 `<输出根>` 原样带到命令里执行（否则会写到当前目录，表现为“乱保存”）。
- 若 `config.json` 缺失、`output_dir` 为空/相对路径/不可写：立即停止并提示用户在网页面板填写，或用脚本参数 `--outdir <绝对路径>` 覆盖。
- 默认只写 `<输出根>/tmp/` 与 `<输出根>/data/`。例外：本地视频加字幕流程的最终输出会按下文规则询问保存位置；用户回答“默认/随便”时允许保存到原视频目录。

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

**代理设置**（可选）：
- 如需访问 YouTube 等受限网站，所有 yt-dlp 命令添加：`--proxy http://127.0.0.1:7890`

**路径说明**：
- **输出根目录**：要求显式配置；临时目录 `<输出根>/tmp/`（下文用 `<输出根>` 指定的根路径）
- **配置方式**：在本技能目录下 `config.json` 设置 `output_dir=<绝对路径>`，或命令行 `--outdir <绝对路径>`（命令行优先）。`output_dir` 为空/缺失/相对路径时，脚本会强制提示用户输入绝对路径并写回 `config.json`，不允许默认回落技能目录。

**转写引擎**（默认走脚本 `scripts/transcribe_srt.py`，自动下模型、零配置）：
- **默认：MLX Whisper / faster-whisper**——首次运行自动下载模型，是烧字幕场景的首选（whisper-cli 没有词级时间戳，字幕会不同步，不要用于烧字幕）。
- **可选备份：whisper-cli**（whisper-cpp）——仅纯转文字、或脚本不可用时才用，需自行 `brew install whisper-cpp` 并把模型下到 `~/.cache/whisper-cpp/`：
  - 精确模式：`~/.cache/whisper-cpp/ggml-large-v3-turbo.bin`（默认模型）
  - 快速模式：`~/.cache/whisper-cpp/ggml-medium.bin`（用户没有要求不允许使用此模型）

**转写模式选择逻辑**：
- **精确模式**（默认）：`ggml-large-v3-turbo.bin`，95% 精度
- **快速模式**：`ggml-medium.bin`，90% 精度，触发条件为用户指令中包含"快速"、"快"或"快速模式"关键词

## 输出路径选择逻辑

**默认**：保存到 `<输出根>/data/`（临时 `<输出根>/tmp/`），不再询问。  
**用户/工作流指定路径**：优先使用指定路径。  
**本地视频加字幕**：默认询问保存位置；“随便/默认”→视频目录，“同名”→覆盖需确认。  
- **避免误写到当前目录**：所有 `-o` 示例都包含 `<输出根>/...`，不要使用裸 `data/…` 相对路径，否则会写到当前工作目录的 `data/`。  
- **首次未配置/配置无效时**：脚本会引导用户手动输入绝对路径并写入 `config.json` 的 `output_dir`（需用户确认，不自动填默认）。若已配置有效值则不再提示，如需重新指定请删除/清空 `config.json` 的 `output_dir` 后运行。

## 使用指导

### 下载整段视频（获取素材）

**使用场景**：下载视频文件和外挂中文字幕，非中文字幕自动翻译成中文。不烧录字幕。

**处理流程**：

1) 下载视频：
```bash
yt-dlp -f "bestvideo[vcodec^=avc1][ext=mp4]+bestaudio[ext=m4a]/bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" \
  --restrict-filenames \
  -o "<输出根>/data/%(title).40s.%(ext)s" \
  "${VIDEO_URL}"
```
- **重要**：优先选择 H.264 (avc1) 编码。YouTube 的 mp4 容器可能装 AV1 编码，而 X/Twitter 等社交平台不支持 AV1，只认 H.264。`vcodec^=avc1` 确保下载 H.264 格式，兼容所有主流平台上传。
- **输出**：`<输出根>/data/<截断标题>.mp4`
- **YouTube 失败自动兜底（推荐）**：如果遇到 `HTTP Error 403` / SABR / PO Token 等问题（近一年 YouTube 风控更严格），建议使用本技能脚本自动重试并从浏览器读取 cookies：
```bash
python3 scripts/youtube_download.py "${VIDEO_URL}"
```
  - 首次尝试会走无 cookies（更快）；失败后会自动用 `--cookies-from-browser chrome` 重试。
  - 如你常用浏览器不是 Chrome：`python3 scripts/youtube_download.py --browser firefox "${VIDEO_URL}"`

2) 下载字幕文件（VTT 格式）：
```bash
yt-dlp --skip-download --write-subs --write-auto-subs \
  --sub-lang "zh-Hans,zh-CN,en,ja" \
  -o "<输出根>/tmp/%(id)s.%(ext)s" \
  "${VIDEO_URL}"
```
- **临时输出**：`<输出根>/tmp/<视频ID>.<语言代码>.vtt`
- 支持外挂字幕和内嵌字幕流

3) 按“字幕处理通用规则”整理字幕（见下文），无字幕则仅保留视频。

**注意事项**：
- 登录/地区限制：提示用户提供 cookies 或切换代理
- 字幕格式：VTT 格式保留时间戳，AI 翻译时保持结构不变
- 硬字幕（烧录字幕）：无法提取，按"无字幕"处理

### 仅下载音频
```bash
yt-dlp -x --audio-format mp3 --embed-thumbnail --add-metadata \
  --restrict-filenames \
  -o "<输出根>/data/%(title).40s.%(ext)s" \
  "${VIDEO_URL}"
```
- 提取音频，嵌入封面和元数据
- 支持多种音频格式（默认 mp3）
- **最终输出**：保存到 `<输出根>/data/<截断标题>.mp3`

### 字幕处理通用规则（单视频/批量共用）
- 中文字幕：`<输出根>/tmp/<视频ID>.zh-Hans.vtt` 或 `.zh-CN.vtt` → 重命名为最终文件名并放入 `<输出根>/data/`（单视频文件名前缀 `<截断标题>`，播放列表前缀 `<视频标题>-<序号>`）。
- 非中文字幕：AI 翻译原 VTT（保时间戳）→ `<输出根>/data/<目标文件名>.zh-Hans.vtt`，删除原字幕。
- 无字幕：保留视频即可。
- 文件名：单视频用 `<截断标题>`，播放列表用 `<视频标题>-<序号>` 对应字幕同名。

### 批量下载播放列表

**使用场景**：YouTube/Bilibili 等平台的播放列表、合集、分P。

**触发关键词**：URL 包含播放列表特征（如 `list=`、BV 开头的合集等）

**交互逻辑**：
1. 检测到播放链接 → 查询播放列表信息（视频数量）
2. **询问用户**："这个播放列表有 X 个视频，要下载哪些？"
3. 用户回答：
   - "全部"、"所有" → 下载所有视频
   - "前5个"、"1-5"、"1:5" → 下载指定范围
   - "第1、3、5个" → 下载指定视频
   - "只下载第一个" → 下载单个视频（`--no-playlist`）

**处理流程**：

1) 批量下载视频到 `<输出根>/data/`（文件名含序号）：
```bash
yt-dlp -f "bestvideo[vcodec^=avc1][ext=mp4]+bestaudio[ext=m4a]/bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" \
  --restrict-filenames \
  --playlist-items 1:5 \
  -o "<输出根>/data/%(title).40s-%(playlist_index)s.%(ext)s" \
  "${PLAYLIST_URL}"
```
- 输出示例：`火星移民计划-1.mp4`。
- 关键：使用 `%(playlist_index)s` 直接写入序号，避免重命名。

2) 对每个视频：下载字幕（同单视频命令）→ 按“字幕处理通用规则”处理，字幕文件名用 `<视频标题>-<序号>`。
- 无字幕：保留对应视频即可。
- 不使用 `--embed-subs`，不烧录字幕。

### 抖音下载
- 命令：`python3 scripts/douyin_download.py <URL> --audio|--video|--list [--resolution 1080p] [--outdir <绝对路径>]`
- 输出根来自 `config.json` 的 `output_dir`（或 `--outdir` 覆盖）；临时文件写入 `<输出根>/tmp/`，最终文件写入 `<输出根>/data/`。
- 脚本会标准化链接为 `/video/<ID>`，使用可见浏览器抓取 aweme detail，成功后自动关闭。未抓到/提示未登录时，运行 `python3 scripts/douyin_login.py` 再重试（状态保存在 `data/browser_state/douyin_profile/`）。
- 若下载失败：先阅读 `抖音初始化.md`，按文档检查登录状态（用登录脚本刷新）、代理/网络、依赖是否缺失，然后重试。

### 为本地视频添加字幕

**使用场景**：用户已下载视频，需要添加中文字幕并烧录到视频画面。

**触发关键词**：`"添加字幕"`、`"补救"`、`"加上字幕"` + 本地视频路径

**处理流程**：

**步骤1：检查是否已有字幕文件**

检查视频所在目录是否存在字幕文件（按优先级）：
1. `<视频标题>.vtt`
2. `<视频标题>.zh-Hans.vtt`
3. `<视频标题>.srt`

**步骤2：根据检查结果选择分支**

├─ **步骤2A：如果已有字幕文件**
│  （跳转到步骤3烧录）
│
└─ **步骤2B：如果没有字幕文件**
   （使用 Whisper 转写后跳转到步骤3烧录）

**步骤2A（已有字幕）**：中文字幕直接用；外语字幕翻译为 `<输出根>/tmp/subtitle_zh.srt|.vtt` 后使用。

**步骤2B（无字幕）**：
1) 提取音频（WAV 格式，16kHz 单声道，Whisper 最佳输入）：`ffmpeg -y -i "/path/to/video.mp4" -vn -acodec pcm_s16le -ar 16000 -ac 1 <输出根>/tmp/audio.wav`
2) Whisper 转写（默认走脚本，自动下模型；烧字幕必须用脚本拿词级时间戳，不能用 whisper-cli）：`python3 scripts/transcribe_srt.py "<输出根>/tmp/audio.wav" --output "<输出根>/tmp/audio.srt" --language <语言>`
   - 可选备份引擎 whisper-cli 仅用于纯转文字，命令与模型路径见上方「转写引擎」
3) 若转写结果非中文，按 `xiaohu-subtitle-polish` 技能的润色规则翻译为 `<输出根>/tmp/audio_zh.srt`，中文则直接使用。
   - 润色要求：去标点、英文中文间加空格、专有名词保留原文、歌词用 ♪ 包裹、去末尾重复/幻觉

**步骤2C：检测视频是否已有硬字幕（烧录前必做）**

烧录新字幕前，必须检查视频画面中是否已有硬编码（烧录过的）字幕：

1. **截帧检查**：在视频有人说话的时间点截一帧（通常 10s 左右）：
```bash
ffmpeg -y -i video.mp4 -ss 00:00:10 -vframes 1 -update 1 /tmp/check_frame.jpg
```
2. **目视确认**：用 Read 工具查看截帧图片，看底部是否有已烧录的文字
3. **如果有已有硬字幕** → 走"避让烧录"流程（见下方步骤 3B）
4. **如果没有已有硬字幕** → 走默认烧录流程（步骤 3A，MarginV=30）

**步骤3A：烧录字幕到视频（无已有硬字幕）**

使用实际验证成功的烧录命令：
```bash
cd "$(dirname "/path/to/video.mp4")"

cp "<视频标题>.mp4" temp_video.mp4
cp "<选定字幕文件>" temp_subs.srt

ffmpeg -y -i temp_video.mp4 \
  -vf "subtitles=temp_subs.srt:force_style='FontName=PingFang SC,Bold=1,FontSize=24,PrimaryColour=&H00FFFFFF,OutlineColour=&H40000000,Outline=1,Shadow=0,MarginV=30'" \
  -c:a copy \
  "<输出文件名>.mp4"
```

**步骤3B：避让烧录（视频已有硬字幕时）**

当视频画面底部已有烧录过的字幕（如英文原字幕），新的中文字幕需要放在已有字幕上方，互不遮挡。

**关键：ASS 的 MarginV 不等于像素值，不能用像素检测值直接填。必须截帧校准。**

流程：

1. **确定初始 MarginV**（根据视频分辨率和已有字幕行数）：

| 视频分辨率 | 已有字幕单行 | 已有字幕可能双行 |
|-----------|------------|----------------|
| 1080p | MarginV=38 | MarginV=50 |
| 720p | MarginV=28 | MarginV=36 |
| 4K | MarginV=55 | MarginV=70 |

> 经验值来源：2026-03-10 Copilot Cowork 视频（1080p，英文字幕单行+双行混合），MarginV=50 验证通过。

2. **用初始值烧录** → 截帧验证（选一帧已有字幕为双行的时间点）：
```bash
ffmpeg -y -i output.mp4 -ss <双行字幕时间点> -vframes 1 -update 1 /tmp/verify.jpg
```

3. **用 Read 查看截帧**：
   - 中文和英文之间有间距、互不遮挡 → 完成
   - 中文还是盖住了英文 → MarginV 加 5 重试
   - 中文离英文太远 → MarginV 减 3 重试

4. **字号建议**：已有硬字幕时，新字幕用 FontSize=22（比默认的 24 小一号），视觉上更协调

**避让烧录命令模板**：
```bash
cd "$(dirname "/path/to/video.mp4")"

cp "<视频标题>.mp4" temp_video.mp4
cp "<选定字幕文件>" temp_subs.srt

ffmpeg -y -i temp_video.mp4 \
  -vf "subtitles=temp_subs.srt:force_style='FontName=PingFang SC,Bold=1,FontSize=22,PrimaryColour=&H00FFFFFF,OutlineColour=&H40000000,Outline=1,Shadow=0,MarginV=50'" \
  -c:a copy \
  "<输出文件名>.mp4"
```

**说明**：
- 先复制视频/字幕为简单文件名（temp_video/temp_subs），避免特殊字符；`-c:a copy` 不重编码。
- 烧录字幕后无法关闭。
- 默认样式：苹方加粗、白字、FontSize=24、轻微半透明黑边（Outline=1）、无阴影、底部留白 30px。此样式经用户确认（2026-02-19，2026-04-24 字号从 20 调到 24）。
- 避让样式：同上但 FontSize=22、MarginV=50（1080p 双行经验值，2026-03-10 验证，2026-04-24 字号从 18 调到 22）。

**步骤4：清理临时文件**
```bash
# 清理 <输出根>/tmp/ 和当前目录临时文件
rm -f "<输出根>/tmp/audio.mp3" "<输出根>/tmp/audio"*.srt "<输出根>/tmp/subtitle_zh".* temp_video.mp4 temp_subs.srt
```

**输出说明**：
- **原视频**：保持不变
- **烧录字幕视频**：默认文件名 `video_with_subs.mp4`（**字幕已烧录到画面**）
- **输出路径**：
  - 默认询问用户："烧录字幕的视频需要保存到哪里？"
  - 用户回答"随便"、"默认" → 保存到原视频所在目录
  - 用户回答"同名" → 覆盖原视频（需确认）
  - 用户指定路径 → 保存到指定位置

## 依赖

**所需依赖**：
- 工具：`yt-dlp`、`ffmpeg`；`whisper-cpp`（可选备份转写引擎，不装也能用）
- Python 包：`mlx-whisper`（Apple 芯片首选）或 `faster-whisper`（通用首选）
- 模型：脚本引擎首次运行自动从 HuggingFace 下载；whisper-cpp 备份引擎需自行把 `ggml-large-v3-turbo.bin`、`ggml-medium.bin` 下到 `~/.cache/whisper-cpp/`

**首次使用或依赖缺失时**：
AI 应自动检测依赖，如发现缺失，**读取 `初始化.md` 文档并按指引自动安装**。

安装完成后返回主流程继续执行用户请求，后续运行无需再次读取初始化文档。

## 临时文件处理

**临时文件位置**：`<输出根>/tmp/`

**临时文件类型**：
- 字幕文件（.vtt, .srt）- YouTube 下载的原始字幕
- 音频文件（.mp3）- Whisper 转写时提取的音频
- 临时复制文件（temp_video.mp4, temp_subs.srt）- 烧录字幕时的简单文件名

**清理策略**：
- 下载/翻译/转写完成后，可清理 `tmp/` 中的原始外文字幕或音频；烧录后清理 temp_video/temp_subs。
- 用户可随时手动清理 `<输出根>/tmp/`；最终输出文件（.mp4/.mp3/.vtt）在 `<输出根>/data/`，不受影响。

## 错误处理

- 字幕下载失败：视频无字幕/地区限制/需 PO token → 提供 cookies 或切换代理。
- 转写失败：模型缺失或音频不支持 → 检查模型、转换音频。
- 视频下载失败：网络/URL/地区限制 → 检查网络、代理或 cookies。
- 磁盘不足：清理 `<输出根>/tmp/`。
- ffmpeg 缺失：按 `初始化.md` 安装依赖后重试。
