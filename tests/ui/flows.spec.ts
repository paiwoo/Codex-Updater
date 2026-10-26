import { test, expect, type Page } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import type { Diagnosis } from '../../src/lib/types';

const diagnosis: Diagnosis = {
  checkedAt: '2026-10-23T05:35:00Z',
  supported: true,
  staged: true,
  updateAvailable: true,
  prompt: 'visible',
  package: {
    name: 'OpenAI.Codex',
    version: '26.1016.6573.0',
    architecture: 'x64',
    publisher: '[test]',
    family: '[test]',
    location: '[test]',
    appId: 'App',
    processes: [{ id: 1, path: '[test]' }],
  },
  offer: {
    version: '26.1016.8622.0',
    architecture: 'x64',
    url: '[test]',
    storeVersion: '26.1016.8622.0',
    releasedAt: null,
  },
  evidence: [
    { code: 'feeds_agree', detail: '', level: 'info' },
    { code: 'registration_blocked', detail: '2026-10-23T05:18:23Z', level: 'warning' },
  ],
};
async function nativeFixture(
  page: Page,
  stage: string | null = null,
  startDelay = 0,
  failure: { code?: string; deployed?: boolean; activity?: 'active' | 'unknown' } = {},
  diagnostic: Diagnosis = diagnosis,
) {
  await page.addInitScript(
    ({ diagnosis, stage, startDelay, failure }) => {
      localStorage.setItem('language', 'zh');
      localStorage.setItem('theme', 'light');
      let run: Record<string, unknown> | null = stage
        ? {
            id: 'test',
            stage,
            code: failure.code || stage,
            startedAt: '2026-10-23T05:35:00Z',
            updatedAt: '2026-10-23T05:35:00Z',
            targetVersion: '26.1016.8622.0',
            beforeVersion: '26.1016.6573.0',
            downloadedBytes: 0,
            totalBytes: null,
            percent: null,
            deployed: failure.deployed || false,
            running: false,
            prompt: 'unverified',
            message: null,
            workerAlive: true,
            activity: failure.activity || 'unknown',
          }
        : null;
      const calls: Array<{ command: string; args: unknown }> = [];
      Object.assign(window, {
        isTauri: true,
        __testCalls: calls,
        __setTestStage: (stage: string, percent: number | null = null) => {
          if (run) Object.assign(run, { stage, percent });
        },
        __TAURI_INTERNALS__: {
          metadata: { currentWindow: { label: 'main' } },
          invoke: async (command: string, args: Record<string, unknown>) => {
            calls.push({ command, args });
            if (command === 'diagnose') return diagnosis;
            if (command === 'snapshot') return { diagnosis, run, history: run ? [run] : [] };
            if (command === 'start_repair') {
              if (startDelay) await new Promise((ok) => setTimeout(ok, startDelay));
              run = {
                id: 'test',
                stage: 'preparing',
                code: 'preparing',
                startedAt: '2026-10-23T05:35:00Z',
                updatedAt: '2026-10-23T05:35:00Z',
                targetVersion: '26.1016.8622.0',
                beforeVersion: '26.1016.6573.0',
                downloadedBytes: 0,
                totalBytes: null,
                percent: null,
                deployed: false,
                running: false,
                prompt: 'unverified',
                message: null,
                workerAlive: true,
              };
              return run;
            }
            if (command === 'resume_repair') {
              if (!run || args.runId !== run.id) throw new Error('Stale recovery request');
              run = {
                ...run,
                id: 'continued',
                stage: run.deployed ? 'launching' : 'preparing',
                code: 'preparing',
                message: null,
              };
              return run;
            }
            if (command === 'control_run') {
              if (run) run.stage = args.action === 'cancel' ? 'cancelled' : 'closing';
              return null;
            }
            if (command === 'export_preview')
              return {
                id: 'preview-id',
                content: JSON.stringify({ schemaVersion: 1, installedVersion: '26.1016.6573.0' }),
              };
            return null;
          },
        },
      });
    },
    { diagnosis: diagnostic, stage, startDelay, failure },
  );
}
test('browser preview is clearly a sample and cannot repair the computer', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByText('设计预览 · 示例数据')).toBeVisible();
  await expect(page.getByRole('button', { name: '查看修复方案' })).toBeDisabled();
  await page.getByRole('button', { name: '偏好设置' }).click();
  await page.getByLabel('语言').selectOption('en');
  await expect(page.getByRole('heading', { name: 'Preferences' })).toBeVisible();
  await page.getByRole('button', { name: 'Dark', exact: true }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
});
const currentDiagnosis: Diagnosis = {
  ...diagnosis,
  checkedAt: '2026-10-26T01:00:00Z',
  staged: false,
  updateAvailable: false,
  prompt: 'not_detected',
  package: {
    ...diagnosis.package!,
    version: '26.1021.3705.0',
    location: 'C:\\Program Files\\WindowsApps\\OpenAI.Codex_26.1021.3705.0',
    processes: [
      { id: 2, path: 'c:/program files/windowsapps/openai.codex_26.1021.3705.0/app/ChatGPT.exe' },
    ],
  },
  offer: { ...diagnosis.offer!, version: '26.1021.3705.0', storeVersion: '26.1021.3705.0' },
  evidence: [{ code: 'feeds_agree', detail: '26.1021.3705.0', level: 'info' }],
};
test('a later current installation replaces the old failure on the home page and keeps its history', async ({
  page,
}) => {
  await nativeFixture(page, 'failed', 0, { code: 'app_in_use' }, currentDiagnosis);
  await page.goto('/');
  await expect(page.getByRole('heading', { name: '本次检查未发现可用更新' })).toBeVisible();
  await expect(page.locator('.run-panel')).toHaveCount(0);
  await expect(page.getByRole('button', { name: '重新退出并继续' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: '查看修复方案' })).toBeDisabled();
  await page.screenshot({
    path: '.local/screenshots/current-with-old-failure.png',
    fullPage: true,
  });
  await page.getByRole('button', { name: '运行记录', exact: true }).click();
  await page.locator('.history-row').filter({ hasText: '修复失败' }).click();
  await expect(page.getByRole('dialog')).toContainText('26.1016.8622.0');
  await expect(page.getByRole('dialog')).toContainText('修复失败');
  expect(
    await page.evaluate(() =>
      (window as unknown as { __testCalls: { command: string }[] }).__testCalls.some((c) =>
        ['resume_repair', 'start_repair', 'control_run'].includes(c.command),
      ),
    ),
  ).toBe(false);
});
test('a running repair stays visible even when a stored diagnosis matches its target', async ({
  page,
}) => {
  await nativeFixture(page, 'deploying', 0, {}, currentDiagnosis);
  await page.goto('/');
  await expect(page.getByRole('heading', { name: '正在修复更新' })).toBeVisible();
  await expect(page.getByRole('progressbar')).toBeVisible();
});
for (const [name, diagnostic] of [
  ['stale diagnosis', { ...currentDiagnosis, checkedAt: '2026-10-22T00:00:00Z' }],
  ['unavailable release feed', { ...currentDiagnosis, offer: null, updateAvailable: null }],
  [
    'old running version',
    {
      ...currentDiagnosis,
      package: { ...currentDiagnosis.package!, processes: diagnosis.package!.processes },
    },
  ],
  [
    'no running version',
    { ...currentDiagnosis, package: { ...currentDiagnosis.package!, processes: [] } },
  ],
] as const) {
  test(`${name} does not hide an unresolved repair`, async ({ page }) => {
    await nativeFixture(
      page,
      'failed',
      0,
      { code: 'launch_unverified', deployed: true },
      diagnostic,
    );
    await page.goto('/');
    await expect(page.locator('.run-context')).toContainText('上次修复记录');
    await expect(page.getByRole('button', { name: '继续启动并验证' })).toBeVisible();
  });
}
test('repair starts only after the user reviews the task-aware plan', async ({ page }) => {
  await nativeFixture(page);
  await page.goto('/');
  await expect(page.getByRole('heading', { name: '新版本，已准备就绪' })).toBeVisible();
  await page.getByRole('button', { name: '查看修复方案' }).click();
  await expect(page.getByRole('dialog')).toContainText('空闲时自动退出 Codex');
  expect(
    await page.evaluate(
      () =>
        (window as unknown as { __testCalls: { command: string }[] }).__testCalls.filter(
          (c) => c.command === 'start_repair',
        ).length,
    ),
  ).toBe(0);
  await page.getByRole('button', { name: '开始修复' }).click();
  await expect(page.getByRole('dialog')).not.toBeVisible();
  await expect(page.getByText('准备修复', { exact: true }).first()).toBeVisible();
});
for (const activity of ['active', 'unknown'] as const) {
  test(`${activity} task state explains why Codex stays open and requires force confirmation`, async ({
    page,
  }) => {
    await nativeFixture(page, 'waiting_for_exit', 0, { activity });
    await page.goto('/');
    await expect(page.locator('.run-heading')).toContainText(
      activity === 'active' ? '检测到任务正在执行' : '无法可靠确认任务状态',
    );
    await page.getByRole('button', { name: '强制结束 Codex…' }).click();
    await expect(page.getByRole('dialog')).toBeVisible();
    await page.getByRole('button', { name: '确认强制结束', exact: true }).click();
    const controls = await page.evaluate(() =>
      (
        window as unknown as { __testCalls: { command: string; args: { action: string } }[] }
      ).__testCalls.filter((call) => call.command === 'control_run'),
    );
    expect(controls.map((call) => call.args.action)).toEqual(['force_exit']);
  });
}
test('reopening an active repair does not start a fresh diagnostic or force quit', async ({
  page,
}) => {
  await nativeFixture(page, 'waiting_for_exit');
  await page.goto('/');
  await expect(page.getByText('等待你处理客户端', { exact: true }).first()).toBeVisible();
  const initial = await page.evaluate(
    () => (window as unknown as { __testCalls: { command: string }[] }).__testCalls,
  );
  expect(initial.some((c) => c.command === 'diagnose' || c.command === 'control_run')).toBe(false);
  await page.getByRole('button', { name: '强制结束 Codex…' }).click();
  await expect(page.getByRole('dialog')).toContainText('这可能中断正在运行的任务');
  await page.getByRole('button', { name: '取消', exact: true }).last().click();
  expect(
    await page.evaluate(
      () =>
        (window as unknown as { __testCalls: { command: string }[] }).__testCalls.filter(
          (c) => c.command === 'control_run',
        ).length,
    ),
  ).toBe(0);
});
test('deployment cannot be cancelled from the interface', async ({ page }) => {
  await nativeFixture(page, 'deploying');
  await page.goto('/');
  await expect(page.getByText('Windows 正在部署', { exact: true }).first()).toBeVisible();
  await expect(page.getByRole('button', { name: '取消', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: '重新检查' })).toHaveCount(0);
  await expect(page.locator('.progress-caption')).toContainText('第 3 / 5 阶段');
  await expect(page.getByRole('progressbar')).not.toHaveAttribute('aria-valuenow');
  await expect(page.locator('.repair-milestones [aria-current="step"]')).toContainText(
    '部署应用包',
  );
  await page.screenshot({ path: '.local/screenshots/deploying.png', fullPage: true });
});
test('polling pauses while hidden, resumes on return, and stops after completion', async ({
  page,
}) => {
  await nativeFixture(page, 'deploying');
  await page.clock.install();
  await page.goto('/');
  await expect(page.getByRole('progressbar')).toBeVisible();
  const count = () =>
    page.evaluate(
      () =>
        (window as unknown as { __testCalls: { command: string }[] }).__testCalls.filter(
          (c) => c.command === 'snapshot',
        ).length,
    );
  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { configurable: true, value: true });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  const hiddenCount = await count();
  await page.clock.runFor(10_000);
  expect(await count()).toBe(hiddenCount);
  await page.evaluate(() => {
    (
      window as unknown as { __setTestStage: (stage: string, percent: number) => void }
    ).__setTestStage('deploying', 42);
    Object.defineProperty(document, 'hidden', { configurable: true, value: false });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await expect(page.getByRole('progressbar')).toHaveAttribute('aria-valuenow', '42');
  await expect(page.locator('.progress-caption')).toContainText('42%');
  await page.evaluate(() =>
    (window as unknown as { __setTestStage: (stage: string) => void }).__setTestStage('complete'),
  );
  await page.clock.runFor(2600);
  await expect(page.getByRole('progressbar')).toHaveCount(0);
  const finishedCount = await count();
  await page.clock.runFor(10_000);
  expect(await count()).toBe(finishedCount);
});
test('slow repair startup still begins polling and waiting for exit pauses the animation', async ({
  page,
}) => {
  await nativeFixture(page, null, 3000);
  await page.goto('/');
  await page.getByRole('button', { name: '查看修复方案' }).click();
  await page.getByRole('button', { name: '开始修复' }).click();
  await expect(page.getByRole('progressbar')).toBeVisible();
  await page.evaluate(() =>
    (window as unknown as { __setTestStage: (stage: string) => void }).__setTestStage(
      'waiting_for_exit',
    ),
  );
  await expect(page.locator('.progress-caption')).toContainText('需要你处理');
  await expect(page.locator('.progress-track')).not.toHaveClass(/indeterminate/);
});
test('visual reference for light and dark previews', async ({ page }) => {
  await mkdir('.local/screenshots', { recursive: true });
  await page.goto('/');
  await expect(page.getByText('设计预览 · 示例数据')).toBeVisible();
  await page.screenshot({ path: '.local/screenshots/light.png', fullPage: true });
  await page.getByRole('button', { name: '外观', exact: true }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await page.screenshot({ path: '.local/screenshots/dark.png', fullPage: true });
  await page.setViewportSize({ width: 780, height: 700 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.screenshot({ path: '.local/screenshots/compact.png', fullPage: true });
});
test('supporting text remains readable and short dialogs can scroll', async ({ page }) => {
  await nativeFixture(page);
  await page.goto('/');
  for (const theme of ['light', 'dark']) {
    await page.evaluate((theme) => {
      document.documentElement.dataset.theme = theme;
    }, theme);
    const metrics = await page.evaluate(() => {
      const style = getComputedStyle(document.documentElement);
      const luminance = (hex: string) => {
        let value = hex.trim().replace('#', '');
        if (value.length === 3) value = [...value].map((c) => c + c).join('');
        const rgb = value
          .match(/../g)!
          .map((v) => parseInt(v, 16) / 255)
          .map((v) => (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
        return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
      };
      const foreground = luminance(style.getPropertyValue('--muted'));
      return {
        ratios: ['--canvas', '--surface', '--sidebar', '--green-soft'].map((token) => {
          const background = luminance(style.getPropertyValue(token));
          return (
            (Math.max(foreground, background) + 0.05) / (Math.min(foreground, background) + 0.05)
          );
        }),
        smallText: [...document.querySelectorAll('main *, aside *')]
          .filter(
            (el) =>
              el.getClientRects().length &&
              [...el.childNodes].some(
                (n) => n.nodeType === Node.TEXT_NODE && n.textContent?.trim(),
              ) &&
              parseFloat(getComputedStyle(el).fontSize) < 12,
          )
          .map((el) => el.textContent),
      };
    });
    expect(metrics.smallText).toEqual([]);
    expect(Math.min(...metrics.ratios)).toBeGreaterThanOrEqual(4.5);
  }
  await page.setViewportSize({ width: 780, height: 540 });
  await page.getByRole('button', { name: '查看修复方案' }).click();
  const dialog = page.getByRole('dialog');
  const bounds = await dialog.boundingBox();
  expect(bounds!.y).toBeGreaterThanOrEqual(20);
  expect(bounds!.y + bounds!.height).toBeLessThanOrEqual(520);
  await page.getByRole('button', { name: '开始修复' }).scrollIntoViewIfNeeded();
  await expect(page.getByRole('button', { name: '开始修复' })).toBeInViewport();
});
for (const failure of [
  { code: 'download_failed', deployed: false, label: '重新下载并继续' },
  { code: 'verification_failed', deployed: false, label: '重新下载并校验' },
  { code: 'launch_unverified', deployed: true, label: '继续启动并验证' },
  { code: 'app_in_use', deployed: false, label: '重新退出并继续' },
  { code: 'access_denied', deployed: false, label: '重试部署' },
]) {
  test(`${failure.code} offers an executable continuation after saved-work confirmation`, async ({
    page,
  }) => {
    await nativeFixture(page, 'failed', 0, failure);
    await page.goto('/');
    if (failure.code === 'download_failed')
      await page.screenshot({ path: '.local/screenshots/recovery.png', fullPage: true });
    await page.getByRole('button', { name: failure.label, exact: true }).click();
    await expect(page.getByRole('dialog')).toContainText('先重新核对安装与任务状态');
    if (failure.code === 'download_failed')
      await page.screenshot({
        path: '.local/screenshots/recovery-plan.png',
        animations: 'disabled',
      });
    const calls = () =>
      page.evaluate(() =>
        (
          window as unknown as { __testCalls: { command: string; args: unknown }[] }
        ).__testCalls.filter((c) => c.command === 'resume_repair'),
      );
    expect(await calls()).toHaveLength(0);
    if (failure.code === 'verification_failed')
      await expect(page.getByRole('dialog')).toContainText('从官方来源重新下载');
    if (failure.code === 'access_denied')
      await expect(page.getByRole('dialog')).toContainText('不会绕过限制');
    await page.getByRole('button', { name: '继续更新' }).click();
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(page.getByRole('progressbar')).toBeVisible();
    expect(await calls()).toEqual([{ command: 'resume_repair', args: { runId: 'test' } }]);
    if (failure.deployed)
      await expect(page.locator('.progress-caption')).toContainText('第 4 / 5 阶段');
    if (failure.code === 'download_failed')
      await page.screenshot({ path: '.local/screenshots/recovery-continued.png', fullPage: true });
  });
}
