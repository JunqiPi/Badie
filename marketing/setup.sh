#!/usr/bin/env bash
# 在你的 Mac 上装好宣传自动化要用的东西。重复运行没关系。
# 用法：在仓库根目录运行 bash marketing/setup.sh
set -euo pipefail
cd "$(dirname "$0")"

need() { command -v "$1" >/dev/null 2>&1; }

if ! need brew; then
  echo "先装 Homebrew：https://brew.sh ，装好后重新运行本脚本。"; exit 1
fi
for pkg in ffmpeg node@22 python@3.12; do
  brew list "$pkg" >/dev/null 2>&1 || brew install "$pkg"
done
export PATH="$(brew --prefix node@22)/bin:$(brew --prefix python@3.12)/bin:$PATH"

# Python：AI 配音（Kokoro，本地运行，不上传任何东西）
[ -d .venv ] || python3.12 -m venv .venv
.venv/bin/pip install -q -r video/requirements.txt

# 配音模型（约 350MB），下载后校验
mkdir -p video/models
fetch() {
  local f=$1 sum=$2
  if [ ! -f "video/models/$f" ] || ! echo "$sum  video/models/$f" | shasum -a 256 -c - >/dev/null 2>&1; then
    curl -fL -o "video/models/$f" "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/$f"
    echo "$sum  video/models/$f" | shasum -a 256 -c -
  fi
}
fetch kokoro-v1.0.onnx 7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5
fetch voices-v1.0.bin  bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d

# Node：画面截图
(cd video && npm install --no-fund --no-audit && npx playwright install chromium)

# 试做一条样片
.venv/bin/python -I video/make_video.py video/scripts/zh-levels.json queue/sample-zh-levels.mp4
echo "装好了。样片在 marketing/queue/sample-zh-levels.mp4"
