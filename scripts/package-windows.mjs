import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, copyFile, readdir, readFile, writeFile, access } from 'node:fs/promises';
import { resolve, join } from 'node:path';

if (process.platform !== 'win32')
  throw new Error('Windows packages must be built and verified on Windows.');
const meta = JSON.parse(await readFile('package.json', 'utf8'));
try {
  await access('.tooling/cargo/bin/cargo.exe');
  process.env.CARGO_HOME = resolve('.tooling/cargo');
  process.env.RUSTUP_HOME = resolve('.tooling/rustup');
  process.env.PATH = resolve('.tooling/cargo/bin') + ';' + process.env.PATH;
} catch {
  /* Standard developer installations are discovered through PATH. */
}
const result = spawnSync(
  process.execPath,
  ['node_modules/@tauri-apps/cli/tauri.js', 'build', '--bundles', 'nsis'],
  { stdio: 'inherit', shell: false },
);
if (result.error || result.status !== 0)
  throw result.error || new Error(`Build exited with ${result.status}`);
const output = resolve('artifacts', meta.version);
await mkdir(output, { recursive: true });
const name = `Codex-Updater_${meta.version}_windows-x64`;
const portable = join(output, `${name}_portable`);
await mkdir(portable, { recursive: true });
await copyFile('src-tauri/target/release/codex-updater.exe', join(portable, 'Codex Updater.exe'));
for (const file of ['LICENSE', 'docs/portable-usage.md'])
  await copyFile(file, join(portable, file.split('/').at(-1)));
await copyFile('THIRD_PARTY_NOTICES.md', join(portable, 'THIRD_PARTY_NOTICES.md'));
await copyFile(
  'src-tauri/resources/THIRD_PARTY_LICENSES.txt',
  join(portable, 'THIRD_PARTY_LICENSES.txt'),
);
const nsisDir = 'src-tauri/target/release/bundle/nsis';
await copyFile(
  join(nsisDir, `Codex Updater_${meta.version}_x64-setup.exe`),
  join(output, `${name}_setup.exe`),
);
const escapePs = (value) => `'${value.replaceAll("'", "''")}'`;
const zip = join(output, `${name}_portable.zip`);
const archive = spawnSync(
  'powershell.exe',
  [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    `Compress-Archive -LiteralPath ${escapePs(portable)} -DestinationPath ${escapePs(zip)} -Force`,
  ],
  { stdio: 'inherit' },
);
if (archive.status !== 0) throw new Error('Could not create portable ZIP.');
const entries = [];
for (const file of (await readdir(output)).filter((file) => /\.(zip|exe)$/.test(file))) {
  const data = await readFile(join(output, file));
  entries.push(`${createHash('sha256').update(data).digest('hex')}  ${file}`);
}
await writeFile(join(output, 'SHA256SUMS.txt'), entries.join('\n') + '\n');
console.log(`Built local release artifacts in ${output}. Nothing has been uploaded.`);
