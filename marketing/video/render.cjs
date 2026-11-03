// 把每个场景画成 1080×1920 的竖版画面（PNG）。
// 用法：node render.cjs <scenes.json> <输出目录>
// scenes.json：{ lang, scenes: [{ caption, url?, image?, text? }] }
// caption 里用 **词** 标出重点词（荧光绿底）。
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const [, , specPath, outDir] = process.argv;
const spec = JSON.parse(fs.readFileSync(specPath, 'utf8'));
const zh = spec.lang === 'zh';
const aiLabel = zh ? 'AI 配音' : 'AI voice';

const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const mark = (s) => esc(s).replace(/\*\*(.+?)\*\*/g, '<mark>$1</mark>');

function card(scene, shot) {
  const body = shot
    ? `<div class="phone"><img src="data:image/png;base64,${shot}"></div>`
    : `<div class="big">${mark(scene.text || '')}</div>`;
  return `<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Nunito:wght@800;900&display=swap" rel="stylesheet">
<style>
*{box-sizing:border-box;margin:0}
body{width:1080px;height:1920px;background:#f5f0e6;color:#17140f;font-family:Nunito,"PingFang SC","Hiragino Sans GB","WenQuanYi Zen Hei",sans-serif;font-weight:900;display:flex;flex-direction:column;align-items:center;padding:150px 70px 110px}
h1{font-size:${zh ? 84 : 88}px;line-height:1.2;text-align:center;letter-spacing:${zh ? '0.02em' : '-0.01em'}}
mark{background:#d4f33f;color:#17140f;padding:0 .18em;border-radius:.2em;box-decoration-break:clone;-webkit-box-decoration-break:clone}
.phone{margin-top:70px;width:640px;height:1240px;border:10px solid #17140f;border-radius:64px;overflow:hidden;box-shadow:18px 18px 0 #17140f;background:#fff}
.phone img{width:100%;display:block}
.big{white-space:pre-line;margin-top:auto;margin-bottom:auto;font-size:${zh ? 110 : 116}px;line-height:1.25;text-align:center;border:10px solid #17140f;border-radius:48px;background:#fff;padding:70px 60px;box-shadow:18px 18px 0 #17140f}
footer{margin-top:auto;width:100%;display:flex;justify-content:space-between;font-size:40px}
.ai{font-size:30px;border:4px solid #17140f;border-radius:999px;padding:6px 22px;background:#c8beff}
</style></head><body>
<h1>${mark(scene.caption || '')}</h1>
${body}
<footer><span>Badie badminton · badie.rsvp</span><span class="ai">${aiLabel}</span></footer>
</body></html>`;
}

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch();
  const phone = await browser.newPage({ viewport: { width: 390, height: 756 }, deviceScaleFactor: 2 });
  const canvas = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
  for (const [i, scene] of spec.scenes.entries()) {
    let shot = null;
    if (scene.url) {
      await phone.goto(scene.url, { waitUntil: 'networkidle' });
      if (scene.scroll) await phone.evaluate((y) => window.scrollTo(0, y), scene.scroll);
      await phone.waitForTimeout(400);
      shot = (await phone.screenshot()).toString('base64');
    } else if (scene.image) {
      shot = fs.readFileSync(path.resolve(path.dirname(specPath), scene.image)).toString('base64');
    }
    await canvas.setContent(card(scene, shot), { waitUntil: 'networkidle' });
    await canvas.screenshot({ path: path.join(outDir, `scene-${String(i).padStart(2, '0')}.png`) });
  }
  await browser.close();
})();
