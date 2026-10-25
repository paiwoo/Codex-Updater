# Changelog / 更新记录

User-visible changes are recorded here. Test versions use Semantic Versioning prerelease identifiers: **alpha → beta → rc → stable**.

此处记录面向用户的变化。测试阶段使用语义化版本后缀，按 **alpha → beta → rc → 正式版** 推进。

## [0.1.0-alpha.1](https://github.com/paiwoo/Codex-Updater/releases/tag/v0.1.0-alpha.1) — 2026-10-26

### First public alpha / 首次公开 Alpha

- Windows x64 diagnosis and repair using verified staged packages or explicitly published official MSIX downloads.
- Independent repair worker, in-app recovery actions, separate deployment/running/prompt results, and redacted export preview.
- English and Simplified Chinese UI, light/dark themes, five-stage progress, and background WebView2 resource management.
- English and Chinese documentation, Windows CI, contribution guidance, and private security reporting.

支持 Windows x64 只读诊断、官方包校验、独立后台修复、失败后继续操作、分项结果与脱敏导出，提供中英文、浅深主题和后台资源管理，并补齐公开维护文档。

### Fixes included / 已包含的修复

- A newer diagnostic confirming the target is installed and running moves an obsolete failed repair out of the home page. Its original record remains in Activity.
- Unresolved launch/version checks and active repairs keep their recovery/progress interface. Terminal repair panels show their timestamp and target versions.
- Package downloads have a separate timeout from feed checks and remain cancellable while waiting for network data.

较新的检查确认目标版本已安装并运行后，首页收起旧失败，原始记录保留；未解决的问题和执行中的任务继续显示。包下载与清单查询分开限时，等待网络数据时仍可取消。

### Known limits / 已知限制

Windows x64 alpha only. Binaries are unsigned. Clean-machine installation and every real failure/recovery branch have not been fully validated. See [validation](docs/validation-alpha.1.md).

仅支持 Windows x64 Alpha 场景，程序未签名；干净机器安装和所有真实失败恢复分支尚未完整验证。
