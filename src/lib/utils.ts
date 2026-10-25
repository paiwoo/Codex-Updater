import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { terminal, type Diagnosis, type RunState } from './types';
export const cn = (...inputs: ClassValue[]) => twMerge(clsx(inputs));
export const bytes = (n: number) =>
  n >= 1048576 ? `${(n / 1048576).toFixed(1)} MB` : `${(n / 1024).toFixed(0)} KB`;
export function versionCompare(a: string, b: string): number {
  const valid = /^\d+\.\d+\.\d+\.\d+$/;
  if (!valid.test(a) || !valid.test(b)) throw new Error('Invalid package version');
  const x = a.split('.').map(Number),
    y = b.split('.').map(Number);
  if ([...x, ...y].some((n) => !Number.isSafeInteger(n) || n > 65535))
    throw new Error('Invalid MSIX version component');
  for (let i = 0; i < 4; i++) {
    if (x[i] !== y[i]) return x[i] > y[i] ? 1 : -1;
  }
  return 0;
}
export function runSuperseded(run: RunState, diagnosis: Diagnosis | null): boolean {
  if (
    !terminal(run.stage) ||
    !diagnosis?.package ||
    diagnosis.updateAvailable === null ||
    !(Date.parse(diagnosis.checkedAt) > Date.parse(run.updatedAt))
  )
    return false;
  const p = diagnosis.package;
  try {
    if (versionCompare(p.version, run.targetVersion) < 0) return false;
  } catch {
    return false;
  }
  const normalize = (path: string) => path.replaceAll('\\', '/').replace(/\/+$/, '').toLowerCase();
  const directory = `${normalize(p.location)}/app`;
  return (
    p.processes.length > 0 &&
    p.processes.every((process) =>
      [`${directory}/chatgpt.exe`, `${directory}/codex.exe`].includes(normalize(process.path)),
    )
  );
}
