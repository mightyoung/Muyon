import { mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const args = process.argv.slice(2);
const value = (name) => { const i = args.indexOf(name); return i < 0 ? undefined : args[i + 1]; };
const baseURL = value('--base-url');
if (!baseURL || !['http:', 'https:'].includes(new URL(baseURL).protocol)) {
  throw new Error('Provide --base-url with the actual authorized preview URL. This script never deploys.');
}
const output = value('--output') ?? '/tmp/muyon-ui-preview-evidence';
const { chromium } = await import('playwright');
const browser = await chromium.launch({ headless: true });
const results = [];
try {
  await mkdir(output, { recursive: true });
  for (const viewport of [{ width: 390, height: 844 }, { width: 1440, height: 900 }]) {
    const page = await browser.newPage({ viewport });
    const errors = [];
    page.on('pageerror', (error) => errors.push(String(error)));
    await page.goto(baseURL, { waitUntil: 'networkidle' });
    // Flutter Web exposes interaction semantics after the accessibility control.
    const accessibility = page.getByRole('button', { name: 'Enable accessibility' });
    if (await accessibility.count()) await accessibility.click({ force: true });
    const button = (name) => page.getByRole('button', { name, exact: true });
    const requireText = async (text) => { await page.getByText(text, { exact: true }).first().waitFor(); };
    await button('UI-4a fixture').click();
    await button('Show original source').click();
    await requireText('Public source B: 10 pieces; unit price 12. Conflicting delivery estimates 3 and 5 days.');
    await button('Apply complete patch').click();
    await requireText('Current surface revision: 2');
    await button('仅这一次').click();
    await page.getByText(/Simulated receipt.*Public memory quantity: 12/).waitFor();
    await button('UI-4a fixture').click();
    await button('拒绝').click();
    await requireText('Confirmation cancelled. No request sent.');
    await button('UI-4a fixture').click();
    const field = page.getByRole('textbox', { name: 'Draft quantity' });
    await field.fill('14');
    await button('Quote B').click();
    await button('Back to comparison').click();
    if (await field.inputValue() !== '14') throw new Error('Draft lost on return');
    await button('Explain').click();
    await requireText('Simulated semantic explanation requested. No model called.');
    const bytes = await page.screenshot({ fullPage: true });
    const name = `${viewport.width}x${viewport.height}.png`;
    await writeFile(`${output}/${name}`, bytes);
    if (errors.length) throw new Error(errors.join('\n'));
    results.push({ viewport, screenshot: name, sha256: createHash('sha256').update(bytes).digest('hex'), publicMemoryPort: true, realHostDatabase: false });
    await page.close();
  }
  await writeFile(`${output}/result.json`, JSON.stringify({ baseURL, browser: browser.version(), results, nativeAndCloudAcceptance: 'not claimed by code/build tests' }, null, 2));
} finally { await browser.close(); }
