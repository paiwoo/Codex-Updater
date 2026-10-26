// Debug-only integration check. An invalid SID makes the child exit before any
// package discovery, exit request, download, or deployment can be performed.
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
const id = randomUUID().replaceAll('-', '');
const restrictiveJob = process.argv.includes('--job');
const root = resolve('.local/detachment', id);
const folder = join(root, 'runs', id);
await mkdir(folder, { recursive: true });
const startedAt = new Date().toISOString();
const state = {
  id,
  stage: 'preparing',
  code: 'preparing',
  startedAt,
  updatedAt: startedAt,
  targetVersion: '1.2.3.4',
  beforeVersion: '1.2.3.3',
  downloadedBytes: 0,
  totalBytes: null,
  percent: null,
  deployed: false,
  running: false,
  prompt: 'unverified',
  message: null,
  workerAlive: false,
};
await writeFile(join(root, 'current.json'), JSON.stringify(id));
await writeFile(
  join(folder, 'request.json'),
  JSON.stringify({ id, targetVersion: '1.2.3.4', sid: 'INVALID_TEST_SID' }),
);
await writeFile(join(folder, 'state.json'), JSON.stringify(state));
const parent = spawn(
  resolve('src-tauri/target/debug/codex-updater.exe'),
  ['--probe-detachment', id],
  {
    windowsHide: true,
    stdio: 'ignore',
    env: {
      ...process.env,
      CODEX_UPDATER_TEST_DATA_DIR: root,
      ...(restrictiveJob ? { CODEX_UPDATER_PROBE_JOB: '1' } : {}),
    },
  },
);
const parentCode = await new Promise((ok, fail) => {
  parent.once('error', fail);
  parent.once('exit', ok);
});
if (parentCode !== 0)
  throw new Error(`The parent could not start an independent worker (${parentCode}).`);
let final;
for (let i = 0; i < 60; i++) {
  const current = JSON.parse(await readFile(join(folder, 'state.json'), 'utf8'));
  if (current.stage === 'failed') {
    final = current;
    break;
  }
  await new Promise((ok) => setTimeout(ok, 250));
}
if (
  !final ||
  final.deployed ||
  final.running ||
  !final.message?.includes('different Windows account')
)
  throw new Error(
    'Expected the detached child to finish its isolated identity rejection after the parent exited.',
  );
await writeFile(
  join(root, 'report.json'),
  JSON.stringify(
    {
      parentExited: true,
      childFinishedAfterParent: true,
      identityRejected: true,
      repairExecuted: false,
      restrictiveJob,
    },
    null,
    2,
  ),
);
console.log(
  `Independent child completed after its parent exited${restrictiveJob ? ' inside a non-breakaway Windows job' : ''}. Invalid identity rejected; no repair was executed.`,
);
