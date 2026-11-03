"""把一个视频脚本（JSON）做成 9:16 的成片：AI 配音 + 品牌画面 + 字幕。

用法：python -I make_video.py <脚本.json> <输出.mp4>
需要：ffmpeg、node（装好 playwright）、以及 setup.sh 装好的 Kokoro 模型。

脚本格式见 scripts/ 里的例子：
{
  "lang": "zh" 或 "en",
  "voice": "zf_xiaoxiao"（中文）/ "af_heart"（英文），
  "speed": 1.0,
  "scenes": [{"say": "配音念的话", "caption": "画面上方的大字，**重点词**", "url": "https://badie.rsvp/zh/levels/"}]
}
每个场景三选一：url（自动截网站手机版）、image（本地图片）、text（大字卡片）。
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import soundfile as sf
from kokoro_onnx import Kokoro

HERE = Path(__file__).resolve().parent
MODELS = Path(os.environ.get("BADIE_TTS_MODELS", HERE / "models"))


def tts(spec, work):
    k = Kokoro(str(MODELS / "kokoro-v1.0.onnx"), str(MODELS / "voices-v1.0.bin"))
    g2p = None
    if spec["lang"] == "zh":
        from misaki import zh
        g2p = zh.ZHG2P()
    durations = []
    for i, scene in enumerate(spec["scenes"]):
        text = scene["say"]
        if g2p:
            audio, sr = k.create(g2p(text), voice=spec["voice"], speed=spec.get("speed", 1.0), is_phonemes=True)
        else:
            audio, sr = k.create(text, voice=spec["voice"], speed=spec.get("speed", 1.0), lang="en-us")
        path = work / f"scene-{i:02d}.wav"
        sf.write(path, audio, sr)
        durations.append(len(audio) / sr + 0.35)  # 每段之间留一点气口
    return durations


def main(spec_path, out_path):
    spec = json.loads(Path(spec_path).read_text(encoding="utf-8"))
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        durations = tts(spec, work)
        subprocess.run(["node", str(HERE / "render.cjs"), str(Path(spec_path).resolve()), str(work)], check=True)
        parts = []
        for i, d in enumerate(durations):
            part = work / f"part-{i:02d}.mp4"
            subprocess.run([
                "ffmpeg", "-v", "error", "-y",
                "-loop", "1", "-t", f"{d:.2f}", "-i", str(work / f"scene-{i:02d}.png"),
                "-i", str(work / f"scene-{i:02d}.wav"),
                "-af", "apad", "-t", f"{d:.2f}",
                "-vf", "scale=1080:1920,format=yuv420p", "-r", "30",
                "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                "-c:a", "aac", "-b:a", "160k", "-ar", "44100", str(part),
            ], check=True)
            parts.append(part)
        listing = work / "list.txt"
        listing.write_text("".join(f"file '{p}'\n" for p in parts))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(listing),
                        "-c", "copy", "-movflags", "+faststart", out_path], check=True)
    print(f"{out_path}  {sum(durations):.1f}s")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
