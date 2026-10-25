export interface ProcessInfo {
  id: number;
  path: string;
}
export interface PackageInfo {
  name: string;
  version: string;
  architecture: string;
  publisher: string;
  family: string;
  location: string;
  appId: string;
  processes: ProcessInfo[];
}
export interface Offer {
  version: string;
  architecture: string;
  url: string;
  storeVersion: string | null;
  releasedAt: string | null;
}
export interface Evidence {
  code: string;
  detail: string;
  level: 'info' | 'warning' | 'error';
}
export interface Diagnosis {
  checkedAt: string;
  package: PackageInfo | null;
  offer: Offer | null;
  staged: boolean;
  supported: boolean;
  updateAvailable: boolean | null;
  prompt: 'visible' | 'not_detected' | 'unverified';
  evidence: Evidence[];
}
export type Stage =
  | 'preparing'
  | 'downloading'
  | 'validating'
  | 'closing'
  | 'waiting_for_exit'
  | 'deploying'
  | 'launching'
  | 'verifying'
  | 'complete'
  | 'failed'
  | 'cancelled'
  | 'interrupted';
export interface RunState {
  id: string;
  stage: Stage;
  code: string;
  startedAt: string;
  updatedAt: string;
  targetVersion: string;
  beforeVersion: string;
  downloadedBytes: number;
  totalBytes: number | null;
  percent: number | null;
  deployed: boolean;
  running: boolean;
  prompt: Diagnosis['prompt'];
  message: string | null;
  workerAlive: boolean;
}
export interface Snapshot {
  diagnosis: Diagnosis | null;
  run: RunState | null;
  history: RunState[];
}
export const terminal = (stage: Stage) =>
  ['complete', 'failed', 'cancelled', 'interrupted'].includes(stage);
