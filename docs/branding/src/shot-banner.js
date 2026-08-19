/* Снимок шапки README: banner.html → PNG 1280×440 (@2x).
 *
 * Зовётся из build_banner.py, руками запускать не нужно.
 */
// Playwright берётся из окружения: путь к нему зависит от машины.
// PLAYWRIGHT=/путь/к/node_modules/playwright перед запуском, если он не рядом.
const path = process.env.PLAYWRIGHT || 'playwright';
const { chromium } = require(path);
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 440 }, deviceScaleFactor: 2 });
  await p.goto('file://' + process.argv[2], { waitUntil: 'networkidle' });
  await p.waitForTimeout(600);
  await p.screenshot({ path: process.argv[3] });
  await b.close();
  console.log('снято');
})();
