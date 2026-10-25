# 0.1.0-alpha.1 validation / 验证记录

Date / 日期：2026-10-26（Asia/Shanghai）。First public alpha / 首次公开 Alpha。

## Verified / 已验证

| Check / 检查                                                       | Result / 结果                                                                         |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| Clean npm install from the official registry / 官方 npm 源干净安装 | Passed with the committed lockfile; no user-specific registry required / 通过         |
| npm security audit / 依赖安全公告检查                              | 0 reported vulnerabilities after updating Vitest to 4.1.12 / 升级测试工具后为 0       |
| TypeScript + Vite production build / 前端生产构建                  | Passed / 通过                                                                         |
| Vitest                                                             | 6 checks passed / 6 项通过                                                            |
| UI flows / 界面流程                                                | 19 checks passed / 19 项通过                                                          |
| Rust                                                               | 19 checks passed / 19 项通过                                                          |
| Formatting and PowerShell syntax / 格式与脚本语法                  | Passed / 通过                                                                         |
| Native read-only smoke / 原生只读联调                              | Passed; 0 page errors; export matched preview / 通过，页面错误为 0，导出与预览一致    |
| Dependency notices / 第三方许可                                    | Generated for 333 locked graph entries with no missing texts / 333 项，无缺失许可文本 |
| ZIP + NSIS + SHA-256 / 发布产物                                    | Built and checked / 已构建并核对                                                      |

The native check read matching installed and offered MSIX versions of `26.1021.3705.0`, with no obsolete repair panel on the home page. The old failed record remained unchanged in history. The UI became accessible in 493 ms on this configured machine; this is not a cold-start guarantee.

原生检查读到的安装包与官方包均为 `26.1021.3705.0`，首页不再显示已过时的失败面板，历史失败记录仍保留。首屏可访问耗时为 493 ms，这是本机单次观测，不是冷启动性能保证。

## Release files / 发布文件

| File / 文件               | Bytes / 字节数 |
| ------------------------- | -------------: |
| Portable ZIP / 便携包     |        2388753 |
| NSIS installer / 安装程序 |        1988143 |

```text
e99eba06db8dab3c41924461da4799de1b8403b138d3230c4f2904a7d43d2a02  Codex-Updater_0.1.0-alpha.1_windows-x64_portable.zip
17c6678bd8170985487340f4c3273051dc6b84570ae8262dd76b25bf8ff05def  Codex-Updater_0.1.0-alpha.1_windows-x64_setup.exe
```

## Limits / 限制

Testing used Windows 10 Pro 22H2 x64 with WebView2 installed. Automated UI tests use sample system results; they do not prove that every real repair failure is recoverable. The native check did not quit, install, or update the active Codex instance. Clean-machine install/uninstall, missing-WebView2 installation, other Windows and enterprise environments, ARM64, and macOS repair remain unverified. Binaries are unsigned. This alpha has not been given stable-release status.

测试环境为 Windows 10 Pro 22H2 x64，已安装 WebView2。界面测试使用模拟系统结果，不能证明所有真实故障均可恢复；原生联调没有退出、安装或升级当前 Codex。干净机器安装与卸载、缺少 WebView2 的安装流程、其他 Windows 与企业环境、ARM64、macOS 修复均未完整验证。程序未签名，当前不属于正式稳定版。

Memory measurements in [the earlier validation record](validation.md) belong to older internal builds. Memory was not remeasured for this documentation and versioning release. / 历史内存数据属于此前内部构建，本次文档与版本整理没有重新测量内存。
