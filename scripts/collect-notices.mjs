import { spawnSync } from 'node:child_process';
import { readFile, readdir, writeFile, mkdir, access } from 'node:fs/promises';
import { dirname, resolve, join } from 'node:path';

try {
  await access('.tooling/cargo/bin/cargo.exe');
  process.env.CARGO_HOME = resolve('.tooling/cargo');
  process.env.RUSTUP_HOME = resolve('.tooling/rustup');
  process.env.PATH = resolve('.tooling/cargo/bin') + ';' + process.env.PATH;
} catch {
  /* Use the developer's standard Cargo installation. */
}
const lock = JSON.parse(await readFile('package-lock.json', 'utf8'));
const entries = [];
for (const [folder, pkg] of Object.entries(lock.packages)) {
  if (!folder || pkg.dev) continue;
  const dir = resolve(folder);
  const meta = JSON.parse(await readFile(join(dir, 'package.json'), 'utf8'));
  entries.push({
    ecosystem: 'npm',
    name: meta.name,
    version: meta.version,
    license: meta.license || pkg.license || 'See license files',
    dir,
  });
}
const metadata = spawnSync(
  'cargo',
  [
    'metadata',
    '--locked',
    '--format-version',
    '1',
    '--filter-platform',
    'x86_64-pc-windows-msvc',
    '--manifest-path',
    'src-tauri/Cargo.toml',
  ],
  { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, windowsHide: true },
);
if (metadata.error || metadata.status !== 0) throw metadata.error || new Error(metadata.stderr);
const graph = JSON.parse(metadata.stdout);
const nodes = new Map(graph.resolve.nodes.map((node) => [node.id, node]));
const included = new Set();
const visit = (id) => {
  if (included.has(id)) return;
  included.add(id);
  for (const edge of nodes.get(id)?.deps || []) visit(edge.pkg);
};
visit(graph.resolve.root);
for (const pkg of graph.packages) {
  if (!included.has(pkg.id)) continue;
  if (!pkg.source) continue;
  entries.push({
    ecosystem: 'cargo',
    name: pkg.name,
    version: pkg.version,
    license: pkg.license || 'See license files',
    dir: dirname(pkg.manifest_path),
    licenseFile: pkg.license_file,
  });
}
const output = [
  'Third-party dependency notices for Codex Updater',
  'Generated from the locked dependency graph. Includes build dependencies and platform alternatives.',
  '',
];
const missing = [];
const supplemental = {
  'cargo/alloc-stdlib': 'alloc-stdlib.txt',
  'cargo/selectors': 'selectors.txt',
  'cargo/webview2-com': 'webview2-rs.txt',
  'cargo/webview2-com-sys': 'webview2-rs.txt',
  'cargo/webview2-com-macros': 'webview2-rs.txt',
  'npm/react-remove-scroll-bar': 'react-remove-scroll-bar.txt',
};
for (const pkg of entries.sort((a, b) =>
  `${a.ecosystem}/${a.name}/${a.version}`.localeCompare(`${b.ecosystem}/${b.name}/${b.version}`),
)) {
  output.push(
    '='.repeat(76),
    `${pkg.ecosystem}: ${pkg.name} ${pkg.version}`,
    `Declared license: ${pkg.license}`,
    '',
  );
  const files = (await readdir(pkg.dir, { withFileTypes: true }))
    .filter((e) => e.isFile() && /^(licen[sc]e|copying|copyright|notice)([._-]|$)/i.test(e.name))
    .map((e) => join(pkg.dir, e.name));
  if (pkg.licenseFile && !files.includes(pkg.licenseFile)) files.push(pkg.licenseFile);
  const supplement = supplemental[`${pkg.ecosystem}/${pkg.name}`];
  if (!files.length && supplement) files.push(resolve('scripts/licenses', supplement));
  if (!files.length) missing.push(`${pkg.ecosystem}: ${pkg.name} ${pkg.version} (${pkg.license})`);
  for (const file of files)
    output.push(`--- ${file.split(/[\\/]/).at(-1)} ---`, await readFile(file, 'utf8'), '');
}
if (missing.length) throw new Error(`Dependency license texts are missing:\n${missing.join('\n')}`);
output.push(await readFile('scripts/licenses/README.md', 'utf8'));
await mkdir('src-tauri/resources', { recursive: true });
await writeFile('src-tauri/resources/THIRD_PARTY_LICENSES.txt', output.join('\n'));
console.log(
  `Collected notices for ${entries.length} locked packages (${missing.length} SPDX-only entries).`,
);
