# 0.1.0-alpha.4 validation / 验证记录

Date / 日期：2026-10-26（Asia/Shanghai）。Windows x64 Alpha。

## Failure and fix / 故障与修复

The affected Windows 10 22H2 machine remained on Codex package `26.1013.4894.0`, with `26.1021.3705.0` staged. Alpha.3 fixed its abrupt PowerShell exit during package-process identity queries. Operating the published alpha.3 through **Continue repair** then exposed a second problem: the Windows launcher's job disallowed worker breakaway, returning access denied (error 5) before shutdown or deployment.

Worker startup now retries without breakaway only for that Windows error. Both attempts create a separate worker with no console and a new process group; neither raises privileges nor changes system policy. The existing worker/deployment locks, account checks, task-state checks, official package validation, and launch verification are retained. If creation still fails, the current failure is refreshed in the interface and the confirmation dialog closes.

A debug-only fixture creates a real Windows job that prohibits breakaway before starting the worker. The check failed before the fix, then passed with it. A deliberately invalid SID makes both normal and restrictive-job checks stop at identity verification, before discovering packages, stopping Codex, or deploying anything. The worker must finish after its parent has exited.

故障机通过 alpha.3 的“继续修复”入口暴露出第二个问题：Windows 启动环境禁止后台进程脱离父作业，返回拒绝访问，尚未退出或部署。alpha.4 只在此错误下用兼容方式重试，保留独立进程、锁、账号与任务检查及包校验，不提权或修改系统策略。补充真实受限 Windows 作业测试，修复前失败、修复后通过；测试使用故意无效的账号标识，验证父进程退出后子进程仍完成账号拒绝，不执行真实修复。

## Checks / 检查

| Check / 检查                                   | Result / 结果                                                                                                                                               |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| TypeScript + Vite / 前端构建                   | Passed / 通过                                                                                                                                               |
| Vitest                                         | 6 passed / 6 项通过                                                                                                                                         |
| UI flows / 界面流程                            | 22 passed, including worker-start failure refresh / 22 项通过，含后台启动失败刷新                                                                           |
| Rust                                           | 22 passed / 22 项通过                                                                                                                                       |
| Parent-exit integration / 父进程退出联调       | Normal and non-breakaway Windows job passed / 正常与受限作业环境均通过                                                                                      |
| Activity and occupancy safety / 任务与占用安全 | Passed, including built GUI helper / 通过，含编译后的图形程序辅助查询                                                                                       |
| Script syntax and formatting / 脚本语法与格式  | Passed / 通过                                                                                                                                               |
| Native smoke / 原生只读联调                    | Passed, no page errors; registered and offered versions agree / 通过，页面错误为 0，版本与发布源一致                                                        |
| GitHub Windows CI / 持续集成                   | [Passed](https://github.com/paiwoo/Codex-Updater/actions/runs/40338801522), including packaging and restrictive-job checks / 含打包与受限作业检查，全部通过 |

## Release files / 发布文件

| File / 文件               | Bytes / 字节数 |
| ------------------------- | -------------: |
| Portable ZIP / 便携包     |        2390279 |
| NSIS installer / 安装程序 |        1988991 |

```text
e38e34385665618f2bb629061d4137b5752ce87705a25a8057a72c2ebf684e7c  Codex-Updater_0.1.0-alpha.4_windows-x64_portable.zip
03d05a989535803c0d1e09e5a623d7da9e970ee7239b5b10c5957ee5298b9627  Codex-Updater_0.1.0-alpha.4_windows-x64_setup.exe
```

## Published-artifact repair / 公开发布包修复

The public alpha.4 ZIP and installer were downloaded without authentication and their SHA-256 values matched the release manifest. The target machine could not complete a direct GitHub TLS download, so the same public ZIP was transferred unchanged and verified again before launch. The executable hash also matched the published portable package.

The native application's **Continue repair** → **Continue update** controls started the worker from the original failed repair. The app confirmed idle tasks, closed the identified Codex processes, verified and registered the staged official package, and launched Codex. The registered version changed from `26.1013.4894.0` to `26.1021.3705.0`.

The first launch check encountered a newly starting desktop process whose executable path was temporarily unavailable. The app retained `deployed=true` and showed **Continue launch & verify**. That native recovery action completed without repeating deployment. Final app state was `complete`, `deployed=true`, `running=true`, `updateAvailable=false`, with no error message and no active worker. Every detected desktop process ran from the target package directory; the copied app-server runtime changed as well. Update-prompt accessibility detection remained `unverified`; absence of the prompt is not claimed.

Both recovery actions were performed in the published native UI through a dedicated, temporary WebView2 endpoint, tunneled over SSH. Personal browser tabs were not used. No generated repair requests, manually edited app state, remote process-kill commands against Codex, or manual package-deployment commands substituted for the application's own repair path. The app was then reopened normally without the temporary debugging endpoint.

公开 ZIP 与安装程序均在未登录状态下载并通过 SHA-256 校验。目标机直连 GitHub TLS 超时，因此将同一份公开 ZIP 原样传输后再次校验，可执行文件也与发布产物一致。

在原生界面点击“继续修复”→“继续更新”，由软件确认任务空闲、退出 Codex、校验并注册已暂存的官方包，再启动新版本。注册版本从 `26.1013.4894.0` 升至 `26.1021.3705.0`。首次启动核对遇到新进程路径暂时不可读，软件保留已部署结果并提供“继续启动并验证”；使用此入口后完成验证，没有重复部署。

最终记录为完成，部署与运行均通过，官方源未提供更高版本，无错误、无活动修复任务；全部桌面进程来自目标新包，后台引擎也切换到新运行时。客户端内部更新提示仍为“未验证”，未声称提示已消失。两次操作均通过公开程序的原生界面完成，使用 SSH 隧道连接该程序专用的临时 WebView2 端点；未连接个人浏览器，没有手工生成修复请求、编辑状态、结束 Codex 或执行包部署来代替软件。完成后关闭临时端点，以普通方式重新打开程序。

## Limits / 限制

Windows x64 only; unsigned binaries. Active-task protection and the new-turn race use fixtures; no real active task was deliberately interrupted. Other Windows policies, clean-machine installation, ARM64, and macOS are not fully validated. Internal task formats can change and require confirmation. The debug-only job fixture is not available in release binaries.

仅支持 Windows x64，程序未签名。执行中任务保护和任务刚开始的竞争情形使用测试夹具，未刻意中断真实任务。其他策略、干净机器安装、ARM64 与 macOS 尚未完整验证。内部任务格式变化时可能要求确认；作业测试夹具不包含在发布程序中。
