import { useEffect, useState } from 'react';
import {
  ArrowDown,
  ArrowDownToLine,
  ArrowRight,
  ArrowUpRight,
  Check,
  CheckCheck,
  CheckCircle2,
  ChevronDown,
  Circle,
  Clock3,
  Download,
  FileJson2,
  History,
  Info,
  LoaderCircle,
  Minus,
  Monitor,
  Moon,
  RefreshCw,
  Settings2,
  ShieldCheck,
  Sparkles,
  Sun,
  TriangleAlert,
  X,
} from 'lucide-react';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { Button } from './components/ui/button';
import { Dialog } from './components/ui/dialog';
import * as client from './lib/client';
import { evidenceText, messages, stageText, type Language } from './lib/i18n';
import { bytes, cn, runSuperseded } from './lib/utils';
import { terminal, type RunState, type Snapshot } from './lib/types';

type Page = 'update' | 'history' | 'settings';
type Theme = 'system' | 'light' | 'dark';
export default function App() {
  const [lang, setLang] = useState<Language>(
    () =>
      (localStorage.getItem('language') as Language) ||
      (navigator.language.startsWith('zh') ? 'zh' : 'en'),
  );
  const [theme, setTheme] = useState<Theme>(
    () => (localStorage.getItem('theme') as Theme) || 'system',
  );
  const [page, setPage] = useState<Page>('update');
  const [data, setData] = useState<Snapshot>({ diagnosis: null, run: null, history: [] });
  const [checking, setChecking] = useState(false),
    [busy, setBusy] = useState(false);
  const [error, setError] = useState(''),
    [repairOpen, setRepairOpen] = useState(false),
    [forceOpen, setForceOpen] = useState(false);
  const [exportOpen, setExportOpen] = useState(false),
    [exportData, setExportData] = useState(''),
    [exportId, setExportId] = useState(''),
    [savedPath, setSavedPath] = useState('');
  const [historyRun, setHistoryRun] = useState<RunState | null>(null);
  const [resumeRun, setResumeRun] = useState<RunState | null>(null);
  const t = messages[lang],
    d = data.diagnosis,
    run = data.run;
  const active = !!run && !terminal(run.stage);
  useEffect(() => {
    localStorage.setItem('theme', theme);
    const media = matchMedia('(prefers-color-scheme: dark)');
    const apply = () =>
      (document.documentElement.dataset.theme =
        theme === 'system' ? (media.matches ? 'dark' : 'light') : theme);
    apply();
    media.addEventListener('change', apply);
    return () => media.removeEventListener('change', apply);
  }, [theme]);
  useEffect(() => {
    localStorage.setItem('language', lang);
    document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
  }, [lang]);
  const check = async () => {
    setChecking(true);
    setError('');
    try {
      const diagnosis = await client.diagnose();
      setData((p) => ({ ...p, diagnosis }));
    } catch (e) {
      setError(String(e));
    } finally {
      setChecking(false);
    }
  };
  useEffect(() => {
    let alive = true;
    client
      .snapshot()
      .then((s) => {
        if (alive) {
          setData(s);
          if (!s.run || terminal(s.run.stage)) void check();
        }
      })
      .catch((e) => {
        if (alive) setError(String(e));
      });
    return () => {
      alive = false;
    };
  }, []); // one initial read; subsequent checks are explicit
  useEffect(() => {
    if (!client.native || !active) return;
    let alive = true;
    let timer: ReturnType<typeof setTimeout>;
    let pending = false;
    const refresh = async () => {
      if (!alive || document.hidden || pending) return;
      pending = true;
      try {
        const s = await client.snapshot();
        if (alive) setData((p) => ({ ...s, diagnosis: s.diagnosis ?? p.diagnosis }));
      } catch (e) {
        if (alive) setError(String(e));
      } finally {
        pending = false;
        if (alive && !document.hidden) timer = setTimeout(refresh, 2500);
      }
    };
    const visibility = () => {
      clearTimeout(timer);
      if (!document.hidden) void refresh();
    };
    timer = setTimeout(refresh, 2500);
    document.addEventListener('visibilitychange', visibility);
    return () => {
      alive = false;
      clearTimeout(timer);
      document.removeEventListener('visibilitychange', visibility);
    };
  }, [active]);
  const action = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    setError('');
    try {
      await fn();
      if (client.native) setData(await client.snapshot());
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  };
  const hero = checking
    ? t.checking
    : active
      ? t.repairing
      : !d
        ? t.welcome
        : d.updateAvailable
          ? d.staged
            ? t.available
            : t.availableDownload
          : d.updateAvailable === false
            ? t.current
            : t.unknown;
  const sub = checking
    ? t.checkingText
    : active
      ? `${run.beforeVersion} → ${run.targetVersion}`
      : !d
        ? t.welcomeText
        : d.updateAvailable
          ? t.availableText
          : d.updateAvailable === false
            ? t.currentText
            : t.unknownText;
  const version = (value: string | undefined, fallback: string) =>
    value ? (
      <span className="version-number">
        {value.split('.').slice(0, 2).join('.')}
        <span>.{value.split('.').slice(2).join('.')}</span>
      </span>
    ) : (
      <span className="version-unavailable">{fallback}</span>
    );
  return (
    <div className={cn('app-shell', active && 'repair-active')}>
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-icon">
            <RefreshCw size={22} strokeWidth={1.8} />
            <ArrowDown size={13} className="brand-arrow" />
          </div>
          <div>
            <strong>Codex Updater</strong>
          </div>
        </div>
        <nav aria-label="Main navigation">
          {(
            [
              { id: 'update', icon: ArrowDownToLine },
              { id: 'history', icon: History },
              { id: 'settings', icon: Settings2 },
            ] as const
          ).map(({ id, icon: Icon }) => (
            <button
              key={id}
              className={cn('nav-item', page === id && 'selected')}
              aria-current={page === id ? 'page' : undefined}
              onClick={() => setPage(id)}
            >
              <Icon size={17} />
              <span>{t[id]}</span>
              {id === 'update' && d?.updateAvailable && <span className="nav-dot" />}
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="sidebar-version">
            <span>
              v0.1.0 <b>ALPHA 2</b>
            </span>
            <span>MIT</span>
          </div>
        </div>
      </aside>
      <div className="workspace">
        <header className="titlebar">
          <div className="drag-region" data-tauri-drag-region>
            <span className="breadcrumb">
              Codex Updater <span>/</span> <b>{t[page]}</b>
            </span>
          </div>
          <div className="header-actions">
            <span className="platform-pill">
              <span />
              {t.platform}
            </span>
            <Button
              size="icon"
              variant="ghost"
              aria-label={t.theme}
              onClick={() =>
                setTheme(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark')
              }
            >
              {theme === 'dark' ? <Sun size={16} /> : <Moon size={16} />}
            </Button>
            {client.native && (
              <div className="window-controls">
                <button aria-label="Minimize" onClick={() => void getCurrentWindow().minimize()}>
                  <Minus size={15} />
                </button>
                <button aria-label={t.close} onClick={() => void getCurrentWindow().close()}>
                  <X size={16} />
                </button>
              </div>
            )}
          </div>
        </header>
        <main>
          {!client.native && (
            <div className="preview-banner">
              <Sparkles size={14} />
              <strong>{t.preview}</strong>
              <span>{t.previewNote}</span>
            </div>
          )}
          {error && (
            <div role="alert" className="error-banner">
              <TriangleAlert size={17} />
              <div>
                <strong>{t.error}</strong>
                <p>{error}</p>
              </div>
              <button aria-label={t.close} onClick={() => setError('')}>
                <X size={15} />
              </button>
            </div>
          )}
          {page === 'update' && (
            <>
              <div className="page-heading">
                <div>
                  <h1>{hero}</h1>
                  <p>{sub}</p>
                </div>
                <div className="hero-emblem">
                  <RefreshCw size={26} className={cn((checking || active) && 'spin-slow')} />
                </div>
              </div>
              {run && !runSuperseded(run, d) && (
                <RunPanel
                  run={run}
                  lang={lang}
                  busy={busy || checking}
                  onCancel={() => void action(() => client.controlRun('cancel'))}
                  onRetry={() => void action(() => client.controlRun('retry'))}
                  onForce={() => setForceOpen(true)}
                  onResume={() => setResumeRun(run)}
                  onCheck={() => void check()}
                />
              )}
              <section className="update-card" aria-label={t.packageVersion}>
                <div className="card-topline">
                  <div className="app-ident">
                    <div className="codex-icon">⌘</div>
                    <div>
                      <strong>Codex</strong>
                      <span>{lang === 'zh' ? '官方桌面客户端' : 'Official desktop app'}</span>
                    </div>
                  </div>
                  <span className="channel-tag">STABLE</span>
                </div>
                <div className="versions">
                  <div>
                    <label>
                      {active ? (lang === 'zh' ? '修复前' : 'Before repair') : t.installed}
                    </label>
                    {version(
                      active ? run.beforeVersion : d?.package?.version,
                      checking ? '…' : t.noPackage,
                    )}
                    <small>{t.packageVersion}</small>
                  </div>
                  <div className="version-arrow">
                    <ArrowRight size={21} />
                  </div>
                  <div>
                    <label>{t.target}</label>
                    {version(
                      active ? run.targetVersion : d?.offer?.version,
                      checking ? '…' : t.noOffer,
                    )}
                    <small>
                      {d?.offer?.architecture || 'x64'} · {t.packageVersion}
                    </small>
                  </div>
                </div>
                <div className="card-status">
                  <div>
                    <span className={cn('status-dot', d?.staged && 'green')} />
                    <span>
                      {d?.updateAvailable
                        ? d.staged
                          ? t.ready
                          : t.direct
                        : d?.updateAvailable === false
                          ? t.noUpdate
                          : t.readOnly}
                    </span>
                  </div>
                  <span className="architecture">
                    {d?.package?.architecture?.toUpperCase() || 'WINDOWS'}
                  </span>
                </div>
                <div className="card-actions">
                  <span>
                    <ShieldCheck size={15} />
                    {t.safe}
                  </span>
                  <div>
                    <Button
                      variant="ghost"
                      onClick={() => void check()}
                      disabled={checking || active}
                    >
                      <RefreshCw size={14} className={cn(checking && 'spin')} />
                      {d ? t.refresh : t.diagnose}
                    </Button>
                    <Button
                      onClick={() => setRepairOpen(true)}
                      disabled={
                        !client.native || !d?.supported || !d?.updateAvailable || active || checking
                      }
                    >
                      {t.repair}
                      <ArrowRight size={15} />
                    </Button>
                  </div>
                </div>
              </section>
              {!active && (
                <section className="conditions">
                  <div className="section-heading">
                    <h2>{t.evidenceTitle}</h2>
                    <span>{t.readOnly}</span>
                  </div>
                  <div className="condition-grid">
                    <Condition
                      icon={ShieldCheck}
                      title={lang === 'zh' ? '官方应用包' : 'Official package'}
                      detail={d?.package ? 'OpenAI.Codex' : '—'}
                      ok={!!d?.package}
                    />
                    <Condition
                      icon={Download}
                      title={
                        d?.staged ? t.ready : lang === 'zh' ? '官方下载源' : 'Official release feed'
                      }
                      detail={d?.offer ? 'persistent.oaistatic.com' : '—'}
                      ok={!!d?.offer}
                    />
                    <Condition
                      icon={Monitor}
                      title={d?.package?.processes.length ? t.running : t.noProcess}
                      detail={
                        d?.package
                          ? `${d.package.processes.length} ${lang === 'zh' ? '个桌面进程' : 'desktop processes'}`
                          : '—'
                      }
                      ok={!!d?.package}
                    />
                  </div>
                </section>
              )}
              {d && (
                <details className="diagnostic-details">
                  <summary>
                    <FileJson2 size={15} />
                    {t.details}
                    <span>
                      {t.checked}{' '}
                      {new Date(d.checkedAt).toLocaleTimeString(lang, {
                        hour: '2-digit',
                        minute: '2-digit',
                      })}
                    </span>
                    <ChevronDown size={15} />
                  </summary>
                  <div className="evidence-list">
                    {d.evidence.map((e, i) => (
                      <div key={i}>
                        <span
                          className={cn('status-dot', e.level === 'info' ? 'green' : 'amber')}
                        />
                        <div>
                          <strong>{evidenceText[lang][e.code] || e.code}</strong>
                          {e.detail && <code>{e.detail}</code>}
                        </div>
                      </div>
                    ))}
                  </div>
                </details>
              )}
            </>
          )}
          {page === 'history' && (
            <>
              <div className="page-heading">
                <div>
                  <h1>{t.history}</h1>
                  <p>
                    {lang === 'zh' ? '每一步，都有真实记录。' : 'A clear record of every step.'}
                  </p>
                </div>
                <History className="muted" size={27} />
              </div>
              {data.history.length ? (
                <div className="history-list">
                  {data.history.map((r) => (
                    <button
                      key={r.id}
                      className="history-row"
                      onClick={() => {
                        setHistoryRun(r);
                      }}
                    >
                      <div className="history-icon">
                        {r.stage === 'complete' ? <CheckCheck size={21} /> : <Clock3 size={21} />}
                      </div>
                      <div>
                        <strong>{stageText[lang][r.stage]}</strong>
                        <span>
                          {r.beforeVersion} → {r.targetVersion}
                        </span>
                      </div>
                      <time>{new Date(r.startedAt).toLocaleString(lang)}</time>
                      <ArrowUpRight size={17} />
                    </button>
                  ))}
                </div>
              ) : (
                <div className="empty-state">
                  <History size={34} />
                  <h2>{t.emptyHistory}</h2>
                  <p>{t.emptyHistoryText}</p>
                </div>
              )}
            </>
          )}
          {page === 'settings' && (
            <>
              <div className="page-heading">
                <div>
                  <h1>{t.settings}</h1>
                  <p>{t.subtitle}</p>
                </div>
                <Settings2 className="muted" size={27} />
              </div>
              <section className="settings-card">
                <h2>{t.theme}</h2>
                <div className="theme-options">
                  {(
                    [
                      { id: 'system', icon: Monitor },
                      { id: 'light', icon: Sun },
                      { id: 'dark', icon: Moon },
                    ] as const
                  ).map(({ id, icon: Icon }) => (
                    <button
                      key={id}
                      aria-pressed={theme === id}
                      className={cn('theme-option', theme === id && 'active')}
                      onClick={() => setTheme(id)}
                    >
                      <Icon size={22} />
                      <span>{t[id]}</span>
                      {theme === id && <Check size={13} />}
                    </button>
                  ))}
                </div>
                <div className="setting-row">
                  <label htmlFor="language">{t.language}</label>
                  <select
                    id="language"
                    value={lang}
                    onChange={(e) => setLang(e.target.value as Language)}
                  >
                    <option value="zh">简体中文</option>
                    <option value="en">English</option>
                  </select>
                </div>
              </section>
              <section className="settings-card">
                <h2>{t.privacy}</h2>
                <p>{t.privacyText}</p>
                <Button
                  variant="outline"
                  disabled={!client.native || busy}
                  onClick={() =>
                    void action(async () => {
                      const preview = await client.exportPreview();
                      setExportData(preview.content);
                      setExportId(preview.id);
                      setSavedPath('');
                      setExportOpen(true);
                    })
                  }
                >
                  <FileJson2 size={16} />
                  {t.export}
                </Button>
              </section>
              <section className="settings-card about">
                <h2>{t.about}</h2>
                <p>{t.aboutText}</p>
                <div>
                  <span>Codex Updater 0.1.0-alpha.2</span>
                  <span>© 2026 paiwoo · MIT</span>
                </div>
              </section>
            </>
          )}
        </main>
        <footer>
          <span>
            <span className="status-dot green" />
            {active ? stageText[lang][run.stage] : t.readOnly}
          </span>
        </footer>
      </div>
      <Dialog
        open={repairOpen}
        onOpenChange={setRepairOpen}
        title={t.repairTitle}
        description={t.repairDescription}
        closeLabel={t.close}
      >
        <div className="repair-target">
          <span>{d?.package?.version}</span>
          <ArrowRight size={18} />
          <strong>{d?.offer?.version}</strong>
        </div>
        <ol className="repair-steps">
          {[t.step1, t.step2, t.step3].map((s, i) => (
            <li key={s}>
              <span>{i + 1}</span>
              {s}
            </li>
          ))}
        </ol>
        <div className="dialog-note">
          <ShieldCheck size={17} />
          <span>{t.preserved}</span>
        </div>
        <div className="dialog-actions">
          <Button variant="ghost" onClick={() => setRepairOpen(false)}>
            {t.cancel}
          </Button>
          <Button
            disabled={busy || !client.native}
            onClick={() =>
              void action(async () => {
                if (d?.offer) {
                  const started = await client.startRepair(d.offer.version);
                  setData((p) => ({ ...p, run: started }));
                  setRepairOpen(false);
                }
              })
            }
          >
            {busy && <LoaderCircle size={15} className="spin" />}
            {t.confirm}
          </Button>
        </div>
      </Dialog>
      <Dialog
        open={!!resumeRun}
        onOpenChange={(open) => {
          if (!open) setResumeRun(null);
        }}
        title={t.recoveryTitle}
        description={t.recoveryDescription}
        closeLabel={t.close}
      >
        <div className="repair-target">
          <span>{resumeRun?.beforeVersion}</span>
          <ArrowRight size={18} />
          <strong>{resumeRun?.targetVersion}</strong>
        </div>
        <p className="recovery-help">
          {resumeRun?.code === 'verification_failed'
            ? t.recoveryFresh
            : resumeRun?.deployed
              ? t.recoveryInstalled
              : t.recoveryRetry}
        </p>
        {resumeRun?.code === 'access_denied' && (
          <p className="recovery-help">{t.permissionLimit}</p>
        )}
        <div className="dialog-actions">
          <Button variant="ghost" onClick={() => setResumeRun(null)}>
            {t.cancel}
          </Button>
          <Button
            disabled={busy || !client.native}
            onClick={() =>
              void action(async () => {
                if (!resumeRun) return;
                const continued = await client.resumeRepair(resumeRun.id);
                setData((p) => ({ ...p, run: continued }));
                setResumeRun(null);
              })
            }
          >
            {busy && <LoaderCircle size={15} className="spin" />}
            {t.recoveryConfirm}
          </Button>
        </div>
      </Dialog>
      <Dialog
        open={forceOpen}
        onOpenChange={setForceOpen}
        title={t.forceTitle}
        description={t.forceText}
        closeLabel={t.close}
      >
        <div className="dialog-actions">
          <Button variant="ghost" onClick={() => setForceOpen(false)}>
            {t.cancel}
          </Button>
          <Button
            variant="danger"
            disabled={busy}
            onClick={() =>
              void action(async () => {
                await client.controlRun('force_exit');
                setForceOpen(false);
              })
            }
          >
            {t.forceConfirm}
          </Button>
        </div>
      </Dialog>
      <Dialog
        open={exportOpen}
        onOpenChange={setExportOpen}
        title={t.exportTitle}
        description={t.exportDescription}
        closeLabel={t.close}
      >
        <pre className="export-preview">{exportData}</pre>
        {savedPath && (
          <p className="saved-path">
            {t.saved} {savedPath}
          </p>
        )}
        <div className="dialog-actions">
          <Button variant="ghost" onClick={() => setExportOpen(false)}>
            {t.close}
          </Button>
          <Button
            disabled={busy || !client.native}
            onClick={() => void action(async () => setSavedPath(await client.saveExport(exportId)))}
          >
            {t.saveExport}
          </Button>
        </div>
      </Dialog>
      <Dialog
        open={!!historyRun}
        onOpenChange={(open) => {
          if (!open) setHistoryRun(null);
        }}
        title={t.history}
        closeLabel={t.close}
        description={historyRun ? new Date(historyRun.startedAt).toLocaleString(lang) : undefined}
      >
        {historyRun && (
          <>
            <div className="repair-target">
              <span>{historyRun.beforeVersion}</span>
              <ArrowRight size={18} />
              <strong>{historyRun.targetVersion}</strong>
            </div>
            <div className="result-grid">
              <div>
                <Clock3 size={14} />
                <span>{stageText[lang][historyRun.stage]}</span>
              </div>
              <div>
                <ShieldCheck size={14} />
                <span>{t.deployment}</span>
                <b>{historyRun.deployed ? t.passed : t.notVerified}</b>
              </div>
              <div>
                <Monitor size={14} />
                <span>{t.launch}</span>
                <b>{historyRun.running ? t.passed : t.notVerified}</b>
              </div>
              <div>
                <Info size={14} />
                <span>{t.prompt}</span>
                <b>
                  {historyRun.prompt === 'visible'
                    ? t.stillVisible
                    : historyRun.prompt === 'not_detected'
                      ? t.notDetected
                      : t.notVerified}
                </b>
              </div>
            </div>
            {historyRun.message && <pre className="export-preview">{historyRun.message}</pre>}
          </>
        )}
      </Dialog>
    </div>
  );
}

function Condition({
  icon: Icon,
  title,
  detail,
  ok,
}: {
  icon: typeof ShieldCheck;
  title: string;
  detail: string;
  ok: boolean;
}) {
  return (
    <div className="condition">
      <div className="condition-icon">
        <Icon size={17} />
      </div>
      <div>
        <strong>{title}</strong>
        <span>{detail}</span>
      </div>
      {ok ? (
        <Check size={13} className="condition-check" />
      ) : (
        <Circle size={12} className="muted" />
      )}
    </div>
  );
}
function RunPanel({
  run,
  lang,
  busy,
  onCancel,
  onRetry,
  onForce,
  onResume,
  onCheck,
}: {
  run: RunState;
  lang: Language;
  busy: boolean;
  onCancel: () => void;
  onRetry: () => void;
  onForce: () => void;
  onResume: () => void;
  onCheck: () => void;
}) {
  const t = messages[lang],
    finished = terminal(run.stage),
    waiting = run.stage === 'waiting_for_exit';
  const step = {
    preparing: 0,
    downloading: 0,
    validating: 0,
    closing: 1,
    waiting_for_exit: 1,
    deploying: 2,
    launching: 3,
    verifying: 4,
    complete: 4,
    failed: 0,
    cancelled: 0,
    interrupted: 0,
  }[run.stage];
  const percent = run.percent === null ? null : Math.round(Math.min(100, Math.max(0, run.percent)));
  const resumeLabel =
    run.deployed || run.code === 'launch_unverified'
      ? t.retryLaunch
      : (
          {
            download_failed: t.retryDownload,
            verification_failed: t.retryValidate,
            app_in_use: t.retryClose,
            access_denied: t.retryDeployment,
          } as Record<string, string>
        )[run.code] || t.continueRepair;
  const failureMessage =
    (
      {
        access_denied: t.accessDenied,
        app_in_use: t.stillInUse,
        verification_failed: t.packageInvalid,
        download_failed: t.downloadFailed,
        launch_unverified: t.launchFailed,
      } as Record<string, string>
    )[run.code] || t.repairFailed;
  const label =
    run.stage === 'complete'
      ? t.completed
      : run.stage === 'failed'
        ? t.failed
        : run.stage === 'cancelled'
          ? t.cancelled
          : run.stage === 'interrupted'
            ? t.interrupted
            : stageText[lang][run.stage];
  return (
    <section className={cn('run-panel', run.stage === 'failed' && 'run-failed')} aria-live="polite">
      {finished && (
        <p className="run-context">
          {t.lastRun} · {new Date(run.startedAt).toLocaleString(lang)} · {run.beforeVersion} →{' '}
          {run.targetVersion}
        </p>
      )}
      <div className="run-heading">
        {finished ? (
          run.stage === 'complete' ? (
            <CheckCircle2 size={21} />
          ) : (
            <TriangleAlert size={21} />
          )
        ) : (
          <LoaderCircle size={21} className={cn(!waiting && 'spin')} />
        )}
        <div>
          <strong>{label}</strong>
          <span>
            {waiting
              ? run.activity === 'active'
                ? t.waitingActive
                : t.waitingUnknown
              : run.stage === 'complete'
                ? t.completeDetail
                : run.stage === 'failed'
                  ? failureMessage
                  : finished
                    ? t.failedDetail
                    : t.stageHelp[run.stage as keyof typeof t.stageHelp]}
          </span>
        </div>
        {!finished &&
          ['preparing', 'downloading', 'validating', 'closing', 'waiting_for_exit'].includes(
            run.stage,
          ) && (
            <Button variant="ghost" size="small" disabled={busy} onClick={onCancel}>
              {t.cancel}
            </Button>
          )}
      </div>
      {!finished && (
        <div className={cn('repair-progress', waiting && 'awaiting-action')}>
          <div className="progress-caption">
            <strong>{lang === 'zh' ? `第 ${step + 1} / 5 阶段` : `Stage ${step + 1} of 5`}</strong>
            <span>{waiting ? t.needsAction : percent === null ? t.working : `${percent}%`}</span>
          </div>
          <div
            className={cn('progress-track', percent === null && !waiting && 'indeterminate')}
            role="progressbar"
            aria-label={stageText[lang][run.stage]}
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={percent ?? undefined}
            aria-valuetext={`${step + 1} / 5 · ${stageText[lang][run.stage]}${percent === null ? '' : ` · ${percent}%`}`}
          >
            <span
              style={
                percent !== null
                  ? { width: `${percent}%` }
                  : waiting
                    ? { width: '100%' }
                    : undefined
              }
            />
          </div>
          <ol
            className="repair-milestones"
            aria-label={lang === 'zh' ? '更新阶段' : 'Update stages'}
          >
            {t.repairSteps.map((title, index) => (
              <li
                key={title}
                className={cn(index < step && 'done', index === step && 'current')}
                aria-current={index === step ? 'step' : undefined}
              >
                <span>{index < step ? <Check size={13} /> : index + 1}</span>
                <strong>{title}</strong>
              </li>
            ))}
          </ol>
          <p className="background-note">{t.background}</p>
        </div>
      )}
      {run.downloadedBytes > 0 && !finished && (
        <div className="download-size">
          {bytes(run.downloadedBytes)}
          {run.totalBytes ? ` / ${bytes(run.totalBytes)}` : ''}
        </div>
      )}
      {waiting && (
        <div className="waiting-actions">
          <Button variant="outline" size="small" onClick={onRetry} disabled={busy}>
            {t.retry}
          </Button>
          <Button variant="ghost" size="small" onClick={onForce} disabled={busy}>
            {t.force}
          </Button>
        </div>
      )}
      {finished && (
        <div className="result-grid">
          {[
            { label: t.deployment, ok: run.deployed },
            { label: t.launch, ok: run.running },
            {
              label: t.prompt,
              ok: run.prompt === 'not_detected',
              value:
                run.prompt === 'visible'
                  ? t.stillVisible
                  : run.prompt === 'unverified'
                    ? t.notVerified
                    : t.notDetected,
            },
          ].map((r) => (
            <div key={r.label}>
              {r.ok ? <CheckCircle2 size={14} /> : <Info size={14} />}
              <span>{r.label}</span>
              <b>{r.value || (r.ok ? t.passed : finished ? t.notVerified : t.pending)}</b>
            </div>
          ))}
        </div>
      )}
      {run.message && (
        <details className="run-error">
          <summary>{t.details}</summary>
          <code>{run.message}</code>
        </details>
      )}
      {finished && (
        <div className="recovery-actions">
          <Button variant="outline" size="small" disabled={busy} onClick={onCheck}>
            <RefreshCw size={14} />
            {t.refresh}
          </Button>
          {run.stage !== 'complete' && (
            <Button size="small" disabled={busy || !client.native} onClick={onResume}>
              {resumeLabel}
              <ArrowRight size={14} />
            </Button>
          )}
        </div>
      )}
    </section>
  );
}
