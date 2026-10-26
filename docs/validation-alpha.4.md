# 0.1.0-alpha.4 validation / 验证记录

Date / 日期：2026-10-26（Asia/Shanghai）。Windows x64 Alpha。

## Failure and fix / 故障与修复

The affected Windows 10 22H2 machine remained on Codex package `26.1013.4894.0`, with `26.1021.3705.0` staged. Alpha.3 fixed its abrupt PowerShell exit during package-process identity queries. Operating the published alpha.3 through **Continue repair** then exposed a second problem: the Windows launcher's job disallowed worker breakaway, returning access denied (error 5) before shutdown or deployment.

Worker startup now retries without breakaway only for that Windows error. Both attempts create a separate worker with no console and a new process group; neither raises privileges nor changes system policy. The existing worker/deployment locks, account checks, task-state checks, official package validation, and launch verification are retained. If creation still fails, the current failure is refreshed in the interface and the confirmation dialog closes.

A debug-only fixture creates a real Windows job that prohibits breakaway before starting the worker. The check failed before the fix, then passed with it. A deliberately invalid SID makes both normal and restrictive-job checks stop at identity verification, before discovering packages, stopping Codex, or deploying anything. The worker must finish after its parent has exited.

故障机通过 alpha.3 的“继续修复”入口暴露出第二个问题：Windows 启动环境禁止后台进程脱离父作业，返回拒绝访问，尚未退出或部署。alpha.4 只在此错误下用兼容方式重试，保留独立进程、锁、账号与任务检查及包校验，不提权或修改系统策略。补充真实受限 Windows 作业测试，修复前失败、修复后通过；测试使用故意无效的账号标识，验证父进程退出后子进程仍完成账号拒绝，不执行真实修复。

## Checks / 检查

| Check / 检查                                   | Result / 结果                                                                                        |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| TypeScript + Vite / 前端构建                   | Passed / 通过                                                                                        |
| Vitest                                         | 6 passed / 6 项通过                                                                                  |
| UI flows / 界面流程                            | 22 passed, including worker-start failure refresh / 22 项通过，含后台启动失败刷新                    |
| Rust                                           | 22 passed / 22 项通过                                                                                |
| Parent-exit integration / 父进程退出联调       | Normal and non-breakaway Windows job passed / 正常与受限作业环境均通过                               |
| Activity and occupancy safety / 任务与占用安全 | Passed, including built GUI helper / 通过，含编译后的图形程序辅助查询                                |
| Script syntax and formatting / 脚本语法与格式  | Passed / 通过                                                                                        |
| Native smoke / 原生只读联调                    | Passed, no page errors; registered and offered versions agree / 通过，页面错误为 0，版本与发布源一致 |

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

The full repair will be performed through the published native application's **Continue repair** interface. The target machine cannot complete a direct GitHub TLS download, so the public ZIP is downloaded and hash-verified on the maintenance computer, transferred unchanged, and verified again before launch. This transports the updater only; no manual Codex deployment or user-data changes substitute for the application's repair path.

完整修复将通过公开发布程序的原生“继续修复”入口执行。目标机直连 GitHub TLS 超时，因此先下载并校验公开 ZIP，原样传输后再次校验。仅传输更新器，不手工部署 Codex 或修改用户数据来代替软件修复。

## Limits / 限制

Windows x64 only; unsigned binaries. Active-task protection and the new-turn race use fixtures; no real active task was deliberately interrupted. Other Windows policies, clean-machine installation, ARM64, and macOS are not fully validated. Internal task formats can change and require confirmation. The debug-only job fixture is not available in release binaries.

仅支持 Windows x64，程序未签名。执行中任务保护和任务刚开始的竞争情形使用测试夹具，未刻意中断真实任务。其他策略、干净机器安装、ARM64 与 macOS 尚未完整验证。内部任务格式变化时可能要求确认；作业测试夹具不包含在发布程序中。
