#!/usr/bin/env bash
#
# xiaohu-video-translate 一键安装脚本
# 把三个技能复制到 ~/.claude/skills/，并从模板生成 config.json
#
# 用法：
#   bash install.sh
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_DIR/skills"
SKILLS_DST="$HOME/.claude/skills"

SKILLS=(xiaohu-video-download xiaohu-video-md xiaohu-subtitle-polish)

echo "==> 安装目标：$SKILLS_DST"
mkdir -p "$SKILLS_DST"

for s in "${SKILLS[@]}"; do
  echo "==> 复制技能：$s"
  rm -rf "$SKILLS_DST/$s"
  cp -R "$SKILLS_SRC/$s" "$SKILLS_DST/$s"

  # 从模板生成 config.json（已存在则不覆盖，保护用户已有配置）
  example="$SKILLS_DST/$s/config.example.json"
  config="$SKILLS_DST/$s/config.json"
  if [ -f "$example" ] && [ ! -f "$config" ]; then
    cp "$example" "$config"
    echo "    已生成 config.json（请按需修改 output_dir）"
  fi
done

echo ""
echo "==> 检查命令行依赖"
missing=()
for bin in yt-dlp ffmpeg; do
  if command -v "$bin" >/dev/null 2>&1; then
    echo "    [OK] $bin"
  else
    echo "    [缺] $bin"
    missing+=("$bin")
  fi
done

# whisper-cli 是可选备份转写引擎，缺了不影响默认流程（默认走 mlx/faster，模型自动下载）
if command -v whisper-cli >/dev/null 2>&1; then
  echo "    [OK] whisper-cli（可选备份引擎）"
else
  echo "    [--] whisper-cli 未装（可选备份引擎，默认走 mlx/faster，不需要它）"
fi

if [ "${#missing[@]}" -gt 0 ]; then
  echo ""
  case "$(uname -s)" in
    Darwin) echo "缺少依赖，用 Homebrew 安装：    brew install ${missing[*]}" ;;
    Linux)  echo "缺少依赖（示例）：              sudo apt install ffmpeg && pip3 install yt-dlp" ;;
    *)      echo "缺少依赖：${missing[*]}（Windows 建议用 WSL，或用 winget / pip 安装）" ;;
  esac
fi

echo ""
echo "==> 检查 Python 转写引擎（任选其一即可）"
if python3 -c "import mlx_whisper" 2>/dev/null; then
  echo "    [OK] mlx-whisper（Apple Silicon Metal GPU 加速，首选）"
elif python3 -c "import faster_whisper" 2>/dev/null; then
  echo "    [OK] faster-whisper（CPU 兜底）"
else
  echo "    [缺] 两个都没有，建议安装其一："
  echo "         pip3 install --break-system-packages mlx-whisper      # Apple Silicon"
  echo "         pip3 install --break-system-packages faster-whisper   # 通用"
fi

echo ""
echo "==> 完成。重启 Claude Code 后，对它说「把这个 YouTube 链接翻译成中文字幕视频」即可。"
echo "    每个技能的输出目录在 ~/.claude/skills/<技能名>/config.json 里改。"
