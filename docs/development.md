# Development / 开发

Prerequisites: Windows x64, Node.js 22.12+ with npm, Rust stable with the MSVC toolchain, Microsoft C++ Build Tools and the Windows SDK, and Microsoft Edge WebView2.

```powershell
git clone https://github.com/paiwoo/Codex-Updater.git
cd Codex-Updater
npm ci
```

Start the native app for real read-only diagnosis:

```powershell
npm run notices                     # Generate bundled dependency licenses
npm run tauri -- dev
```

For the browser design preview with sample data only, run `npm run dev` instead.

Verify and package:

```powershell
npm run build
npm test
npx playwright install chromium
npm run test:ui
npm run format:check
powershell.exe -File scripts/native.ps1 -Action test
powershell.exe -File scripts/native.ps1 -Action build
node scripts/test-detachment.mjs
node scripts/test-detachment.mjs --job
powershell.exe -File scripts/check-windows-scripts.ps1
powershell.exe -File scripts/test-windows-activity.ps1
npm run package:windows
powershell.exe -File scripts/test-windows-activity.ps1 -ProcessHelper src-tauri/target/release/codex-updater.exe
```

`package:windows` generates dependency notices, a portable ZIP, an NSIS installer, and checksums under `artifacts/<version>/`. [Windows CI](../.github/workflows/ci.yml) runs on pushes and pull requests. UI tests use a managed browser and do not perform a real repair or connect to personal Chrome.

## 从源码构建

需要 Windows x64、Node.js 22.12+ 和 npm、Rust stable 的 MSVC 工具链、Microsoft C++ Build Tools 与 Windows SDK，以及 Microsoft Edge WebView2。

```powershell
git clone https://github.com/paiwoo/Codex-Updater.git
cd Codex-Updater
npm ci
```

启动原生程序，进行本机只读诊断：

```powershell
npm run notices                     # 生成原生程序需要的第三方许可
npm run tauri -- dev
```

仅查看使用示例数据的浏览器设计预览时，改用 `npm run dev`。

检查与打包：

```powershell
npm run build
npm test
npx playwright install chromium
npm run test:ui
npm run format:check
powershell.exe -File scripts/native.ps1 -Action test
powershell.exe -File scripts/native.ps1 -Action build
node scripts/test-detachment.mjs
node scripts/test-detachment.mjs --job
powershell.exe -File scripts/check-windows-scripts.ps1
powershell.exe -File scripts/test-windows-activity.ps1
npm run package:windows
powershell.exe -File scripts/test-windows-activity.ps1 -ProcessHelper src-tauri/target/release/codex-updater.exe
```

`package:windows` 会生成第三方许可、便携 ZIP、NSIS 安装程序和校验清单，位于 `artifacts/<version>/`。[Windows CI](../.github/workflows/ci.yml) 在推送和 PR 时检查构建。界面测试使用独立测试浏览器，不连接个人 Chrome，也不执行真实修复。
