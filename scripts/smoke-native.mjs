// Tests only the newly built application. It never connects to personal Chrome
// and never confirms a repair or requests Codex to exit.
import { chromium } from '@playwright/test';
import { spawn, spawnSync } from 'node:child_process';
import { mkdir, writeFile, readFile, unlink } from 'node:fs/promises';
import { resolve, basename } from 'node:path';
import { createServer } from 'node:net';

if (process.platform !== 'win32') throw new Error('Native smoke check requires Windows.');
const executable = resolve(process.argv[2] || 'src-tauri/target/release/codex-updater.exe');
const expectCurrent = process.argv.includes('--expect-current');
const output = resolve('.local/native');
await mkdir(output, { recursive: true });
const listener = createServer();
await new Promise((ok, fail) => {
  listener.once('error', fail);
  listener.listen(0, '127.0.0.1', ok);
});
const port = listener.address().port;
await new Promise((ok) => listener.close(ok));
const launchedAt = performance.now();
const app = spawn(executable, [], {
  windowsHide: true,
  stdio: 'ignore',
  env: {
    ...process.env,
    WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS: `--remote-debugging-port=${port} --remote-debugging-address=127.0.0.1`,
    WEBVIEW2_USER_DATA_FOLDER: resolve('.local/native/webview-profile'),
  },
});
const errors = [];
let browser;
try {
  let endpoint;
  for (let i = 0; i < 100; i++) {
    if (app.exitCode !== null) throw new Error(`Native app exited early (${app.exitCode}).`);
    try {
      const reply = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (reply.ok) {
        endpoint = (await reply.json()).webSocketDebuggerUrl;
        break;
      }
    } catch {
      /* The app may still be starting. */
    }
    await new Promise((ok) => setTimeout(ok, 200));
  }
  if (!endpoint)
    throw new Error('The test app did not expose its temporary WebView2 test endpoint.');
  browser = await chromium.connectOverCDP(endpoint);
  const context = browser.contexts()[0];
  const pages = context.pages();
  const page =
    pages.find((p) => p.url().includes('tauri.localhost') || p.url().startsWith('tauri:')) ||
    pages[0];
  if (!page) throw new Error('No app WebView found.');
  page.on('pageerror', (error) => errors.push(String(error)));
  await page.waitForSelector('.page-heading h1', { timeout: 20_000 });
  const interfaceReadyMs = Math.round(performance.now() - launchedAt);
  const native = await page.evaluate(() => !!window.isTauri);
  if (!native || (await page.locator('.preview-banner').count()))
    throw new Error('Native app unexpectedly showed a sample preview.');
  await page.waitForFunction(
    () =>
      document.querySelectorAll('.version-number').length >= 1 &&
      !document.querySelector('.hero-emblem .spin-slow'),
    undefined,
    { timeout: 120_000 },
  );
  const result = await page.evaluate(() => ({
    title: document.querySelector('h1')?.textContent,
    versions: [...document.querySelectorAll('.version-number')].map((el) => el.textContent),
    errors: [...document.querySelectorAll('.error-banner')].map((el) => el.textContent),
    runPanels: document.querySelectorAll('.run-panel').length,
  }));
  if (result.errors.length)
    throw new Error(`Native diagnostic failed: ${result.errors.join(' / ')}`);
  if (result.versions.length < 1) throw new Error('Real package version was not displayed.');
  if (
    expectCurrent &&
    (result.runPanels !== 0 ||
      result.versions.length !== 2 ||
      result.versions[0] !== result.versions[1])
  )
    throw new Error('Expected the current package without an obsolete repair panel.');
  await page.screenshot({ path: resolve(output, 'native-system.png'), fullPage: true });
  await page.locator('.header-actions > button').first().click();
  await page.screenshot({ path: resolve(output, 'native-alternate.png'), fullPage: true });
  const repairButton = page.locator('.card-actions .button-primary');
  if (await repairButton.isEnabled()) {
    await repairButton.click();
    await page.waitForSelector('[role="dialog"]');
    await page.screenshot({ path: resolve(output, 'native-repair-plan.png'), fullPage: true });
    // Close the preview, deliberately never click the saved-work confirmation.
    await page.locator('.dialog-close').click();
  }
  await page.locator('.nav-item').nth(2).click();
  await page.locator('.settings-card .button-outline').click();
  await page.waitForSelector('.export-preview');
  const redacted = JSON.parse(await page.locator('.export-preview').innerText());
  if (expectCurrent && redacted.diagnosis.updateAvailable !== false)
    throw new Error('Expected a successful release check with no available update.');
  const raw = JSON.stringify(redacted);
  for (const forbidden of [
    '"processes"',
    '"location"',
    '"message"',
    '"path"',
    '"sid"',
    'C:\\Users\\',
    'auth.json',
  ]) {
    if (raw.includes(forbidden)) throw new Error(`Export contains unexpected field ${forbidden}`);
  }
  await page.locator('[role="dialog"] .button-primary').click();
  await page.waitForSelector('.saved-path');
  const savedText = await page.locator('.saved-path').innerText();
  const savedPath = savedText.replace(/^(已保存到|Saved to)\s+/, '');
  if (!/^codex-updater-diagnostic-[\w-]+\.json$/.test(basename(savedPath)))
    throw new Error('Unexpected diagnostic export name.');
  if (JSON.stringify(JSON.parse(await readFile(savedPath, 'utf8'))) !== raw)
    throw new Error('Saved export differs from the reviewed preview.');
  await unlink(savedPath);
  await page.locator('.dialog-close').click();
  await page.locator('#language').selectOption('en');
  await page.screenshot({ path: resolve(output, 'native-settings-en.png'), fullPage: true });
  const report = {
    executable,
    processId: app.pid,
    interfaceReadyMs,
    native,
    diagnosis: result,
    diagnostic: redacted,
    pageErrors: errors,
    repairExecuted: false,
    exportMatchesPreview: true,
  };
  const memory = spawnSync(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      `$all=Get-CimInstance Win32_Process; $ids=@(${app.pid}); do { $next=@($all | Where-Object { $_.ParentProcessId -in $ids -and $_.ProcessId -notin $ids } | Select-Object -ExpandProperty ProcessId); $ids+=$next } while($next.Count -gt 0); $p=@(Get-Process -Id $ids -ErrorAction SilentlyContinue); @{processCount=$p.Count;workingSetBytes=($p | Measure-Object WorkingSet64 -Sum).Sum;privateBytes=($p | Measure-Object PrivateMemorySize64 -Sum).Sum} | ConvertTo-Json -Compress`,
    ],
    { encoding: 'utf8', windowsHide: true },
  );
  report.memory = memory.status === 0 ? JSON.parse(memory.stdout) : null;
  await writeFile(resolve(output, 'smoke-report.json'), JSON.stringify(report, null, 2));
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(
    JSON.stringify({
      native,
      interfaceReadyMs,
      versions: result.versions,
      pageErrors: errors.length,
      repairExecuted: false,
    }),
  );
  // The close button targets this test application only.
  await page.getByRole('button', { name: 'Close', exact: true }).click();
} finally {
  if (browser) await browser.close().catch(() => {});
  if (app.exitCode === null) {
    await new Promise((ok) => {
      const timeout = setTimeout(ok, 3000);
      app.once('exit', () => {
        clearTimeout(timeout);
        ok();
      });
    });
    if (app.exitCode === null) app.kill();
  }
}
