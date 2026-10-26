# Contributing / 参与贡献

Codex Updater is personally maintained by [Kabi (paiwoo)](https://github.com/paiwoo) to fix failed Codex desktop updates. Bug reports and focused contributions are welcome.

本项目由 [Kabi（paiwoo）](https://github.com/paiwoo) 个人维护，用于解决 Codex 桌面端更新失败，欢迎反馈问题和提交相关改进。

Issues and pull requests may be written in English or Simplified Chinese.

Issue 和 PR 均可使用英文或简体中文。

## Before opening an issue / 提交问题前

- Search existing issues and check the [support and validation scope](docs/validation.md).
- Include the updater version, Windows version and architecture, Codex installation channel, reproduction steps, and expected versus actual behavior.
- Use the app's redacted export if it helps explain the problem. Review it before sharing; do not attach the full runtime directory, credentials, chats, or private configuration.
- Use [private security reporting](SECURITY.md) for security-sensitive information.

请先搜索已有问题、确认支持范围，并说明工具版本、Windows 版本与架构、Codex 安装渠道、复现步骤、预期与实际行为。可附上已检查的脱敏导出，不要上传原始运行目录或认证信息。安全问题使用私密报告。

GitHub Issues track reproducible bugs, actionable requests, and public work. Day-to-day investigation and experiments belong in ignored local `.scratch/` files. Do not automatically publish raw work notes.

GitHub Issues 用于明确、可协作的公开事项；日常思考和试错留在本地 `.scratch/`，整理后再公开。

## Development / 开发

Follow the setup in [English](README.md#build-from-source) or [简体中文](README.zh-CN.md#从源码构建). Preserve the lockfiles and use the existing stack and helpers.

```powershell
npm ci
npm run build
npm test
npx playwright install chromium
npm run test:ui
npm run format:check
powershell.exe -File scripts/native.ps1 -Action test
powershell.exe -File scripts/check-windows-scripts.ps1
```

Use `npm run tauri -- dev` for native read-only diagnosis. A browser preview uses sample data and cannot validate a real installation. Automated tests must not silently close or repair a developer's Codex. Use an isolated test environment for real deployment tests and document what was changed.

原生诊断使用 `npm run tauri -- dev`。浏览器预览仅用示例数据；自动化测试不得静默关闭或修复开发者正在使用的 Codex。真实部署测试请使用隔离环境并记录变更。

## Pull requests / 提交变更

- Keep each PR focused on one problem and explain behavior before and after the change.
- Add a regression check for meaningful logic changes. Report checks actually run and any limits of the evidence.
- Update both READMEs when user instructions change; update both UI languages for new interface copy.
- Follow [GLOSSARY.md](GLOSSARY.md). Keep package version, running version, and prompt observation distinct. Record important design changes in `docs/adr/`.
- Preserve package-source, signature, identity, user/session, and process validation. Do not add uninstall/reset, credential edits, automatic force quit, or policy bypasses as recovery shortcuts.
- Use concise commit subjects such as `fix: keep historical failures out of current status` or `docs: clarify portable setup`.

PR 聚焦一个问题，说明行为变化、验证结果与限制。用户说明同时更新中英文，重要逻辑增加回归检查。沿用术语表和已有安全边界，避免将卸载、重置、修改认证或跳过校验作为修复捷径。

## Releases / 版本发布

Use Semantic Versioning with `alpha`, `beta`, and `rc` prerelease identifiers. Mark these GitHub releases as prereleases. Keep `package.json`, its lockfile, Cargo manifests and lockfile, Tauri config, UI version, and release tag in sync. Never relabel an old binary as a newer release: rebuild and verify its checksums and notices.

使用带 `alpha`、`beta`、`rc` 标识的语义化版本，并在 GitHub 标为预发布。同步 npm、Cargo、Tauri、界面和 Git 标签的版本；发布前重新构建并核对校验值和第三方许可，不将旧二进制改名冒充新版本。

Changes are contributed under the project's [MIT License](LICENSE). Keep third-party attribution intact.
