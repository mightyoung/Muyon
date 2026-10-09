import { mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
const args = process.argv.slice(2);
const arg = (name) => { const i = args.indexOf(name); return i < 0 ? undefined : args[i + 1]; };
const base = arg('--base-url');
if (!base || !['http:', 'https:'].includes(new URL(base).protocol)) throw new Error('Provide an authorized preview --base-url. This script never deploys.');
const url = new URL(base); url.searchParams.set('workspace', '1');
const output = arg('--output') ?? '/tmp/muyon-ui3b-browser-evidence';
const { chromium } = await import('playwright');
const browser = await chromium.launch({ headless: true });
const results = [];
try {
  await mkdir(output, { recursive: true });
  for (const viewport of [{ width: 390, height: 844 }, { width: 1440, height: 900 }]) {
    const page = await browser.newPage({ viewport });
    const errors = []; page.on('pageerror', (e) => errors.push(String(e)));
    const enable = async () => {
      const a = page.getByRole('button', { name: 'Enable accessibility' });
      if (await a.count()) await a.click({ force: true });
    };
    await page.goto(url.href, { waitUntil: 'networkidle' }); await enable();
    const field = page.getByRole('textbox', { name: 'Draft quantity' });
    await field.fill('14');
    await page.getByRole('button', { name: 'Save checkpoint', exact: true }).click();
    // Durability assertion queries the public projection rather than sleeping.
    await page.waitForFunction(() => Object.keys(localStorage).some((k) => k.startsWith('muyon-public-workspace:') && JSON.parse(localStorage[k]).userOverrides.quantity === '14'));
    await page.getByRole('button', { name: 'Patch workspace', exact: true }).click();
    await page.waitForFunction(() => Object.keys(localStorage).some((k) => k.startsWith('muyon-public-workspace:') && JSON.parse(localStorage[k]).planRevision === 2));
    await page.reload({ waitUntil: 'networkidle' }); await enable();
    await page.getByText('Current surface revision: 2', { exact: true }).waitFor();
    if (await field.inputValue() !== '14') throw new Error('Manual override lost after browser reload');
    const image = await page.screenshot({ fullPage: true });
    const name = `${viewport.width}x${viewport.height}.png`; await writeFile(`${output}/${name}`, image);
    if (errors.length) throw new Error(errors.join('\n'));
    results.push({ viewport, screenshot: name, sha256: createHash('sha256').update(image).digest('hex'), browserFixtureOnly: true, nativeSQLite: false });
    await page.close();
  }
  await writeFile(`${output}/result.json`, JSON.stringify({ baseURL: url.href, browser: browser.version(), results }, null, 2));
} finally { await browser.close(); }
