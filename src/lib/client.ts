import { invoke, isTauri } from '@tauri-apps/api/core';
import type { Diagnosis, RunState, Snapshot } from './types';
export const native = isTauri();
const demo: Diagnosis = {
  checkedAt: new Date().toISOString(),
  supported: true,
  staged: true,
  updateAvailable: true,
  package: {
    name: 'OpenAI.Codex',
    version: '26.1001.1000.0',
    architecture: 'x64',
    publisher: 'Example Publisher',
    family: 'EXAMPLE',
    location: '[sample]',
    appId: 'App',
    processes: [{ id: 0, path: '[sample]' }],
  },
  offer: {
    version: '26.1002.2000.0',
    architecture: 'x64',
    url: '[sample]',
    storeVersion: '26.1002.2000.0',
    releasedAt: null,
  },
  prompt: 'unverified',
  evidence: [
    { code: 'staged_ready', detail: '', level: 'info' },
    { code: 'app_running', detail: '1', level: 'warning' },
  ],
};
export const diagnose = () => (native ? invoke<Diagnosis>('diagnose') : Promise.resolve(demo));
export const snapshot = () =>
  native
    ? invoke<Snapshot>('snapshot')
    : Promise.resolve({ diagnosis: null, run: null, history: [] });
export const startRepair = (targetVersion: string) =>
  invoke<RunState>('start_repair', { targetVersion });
export const resumeRepair = (runId: string) => invoke<RunState>('resume_repair', { runId });
export const controlRun = (action: 'cancel' | 'force_exit' | 'retry') =>
  invoke<void>('control_run', { action });
export const exportPreview = () => invoke<{ id: string; content: string }>('export_preview');
export const saveExport = (previewId: string) => invoke<string>('save_export', { previewId });
