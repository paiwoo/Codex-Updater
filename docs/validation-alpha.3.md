# 0.1.0-alpha.3 validation / 验证记录

Date / 日期：2026-10-26（Asia/Shanghai）。Windows x64 Alpha。

## Failure and fix / 故障与修复

An affected Windows 10 22H2 x64 installation had Codex package `26.1013.4894.0` registered and `26.1021.3705.0` staged. Both the original repair and **Continue repair** stopped before deployment with `System operation Quit did not return a valid result` and an empty error stream.

A read-only probe in the existing interactive Windows account reproduced an abrupt PowerShell exit at `Add-Type -TypeDefinition`, before the package-identity API was called. The scheduled process returned `0xFFFFFFFF`; no matching application-crash event was found. Security software was installed, but the investigation did not establish which component terminated the process.

Package-process identity queries now run in the compiled Rust application through a bounded, read-only helper command. PowerShell retains the current-user/session and parent-process checks. No runtime code compilation, security-setting changes, account creation, elevation, uninstall, or app-data reset is required by this fix. Task checks remain conservative: unknown or active tasks are not automatically stopped. The updater and the inspection process are excluded from shutdown candidates.

一台 Windows 10 22H2 x64 设备注册旧包、暂存新包，首次修复与“继续修复”均在退出检查阶段中断。只读探针定位到 PowerShell 临时编译代码时直接退出，尚未执行应用包身份 API；未确认具体终止来源。修复将该查询移入已编译的 Rust 程序，保留账号、会话、关联进程和任务状态检查，并排除更新器与检查进程自身。无需修改安全设置或重置应用数据。

## Checks before publication / 发布前检查

| Check / 检查                                      | Result / 结果                                                                                                                                                               |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| TypeScript + Vite production build / 前端构建     | Passed / 通过                                                                                                                                                               |
| Vitest                                            | 6 passed / 6 项通过                                                                                                                                                         |
| UI flows / 界面流程                               | 21 passed / 21 项通过                                                                                                                                                       |
| Rust                                              | 22 passed, including native query input limits and missing processes / 22 项通过，含原生查询输入边界与消失进程                                                              |
| Windows script syntax / 脚本语法                  | Passed / 通过                                                                                                                                                               |
| Native read-only smoke / 原生只读联调             | No page errors; registered and offered versions agree / 页面错误为 0，注册版本与官方源一致                                                                                  |
| Affected-machine read-only query / 故障机只读查询 | Passed in the existing interactive session: desktop processes and copied app-server found, task idle, updater excluded / 通过，正确识别桌面与后台引擎，任务空闲，排除更新器 |
| Activity and occupancy safety / 任务与占用安全    | Passed: active/idle/unknown, force confirmation, stale locks, bounded reads, new-turn race, helper failure, account/session filters, app-server, self-protection / 全部通过 |
| Third-party notices / 第三方许可                  | 333 locked packages, no missing texts / 333 项，无缺失文本                                                                                                                  |
| Windows packaging / Windows 打包                  | Portable ZIP, NSIS installer and SHA-256 manifest built / 已生成便携 ZIP、安装程序与校验清单                                                                                |

## Release files / 发布文件

| File / 文件               | Bytes / 字节数 |
| ------------------------- | -------------: |
| Portable ZIP / 便携包     |        2390437 |
| NSIS installer / 安装程序 |        1989312 |

```text
e5c46de99e17bc14b2ddd9a0d79e0d7ac981fa9db8b2d201696115642dd99e23  Codex-Updater_0.1.0-alpha.3_windows-x64_portable.zip
94e017dbf5bb170cf96af1a8d5654cfef304840657e20a2c135a2955e6ea6a28  Codex-Updater_0.1.0-alpha.3_windows-x64_setup.exe
```

## Limits / 限制

The published artifact was downloaded, verified, installed, and operated through its native **Continue repair** interface on the affected machine. Package-process queries passed, but the Windows launcher denied worker creation with error 5 before any shutdown or deployment. The updater recorded `worker_start_failed`. This additional compatibility issue is addressed in [alpha.4](validation-alpha.4.md); alpha.3 alone did not complete the update on this machine. No manual remote package deployment was used.

Windows x64 only. Binaries are unsigned. Other Windows security policies and clean-machine installation have not been fully validated. Task detection depends on internal lifecycle formats and requires confirmation when they cannot be recognized. No real active task was deliberately interrupted.

发布后使用公开下载并校验的 alpha.3，在原生界面操作“继续修复”。进程查询通过，但 Windows 启动环境拒绝创建后台任务，记录 `worker_start_failed`，尚未退出 Codex 或部署。此项兼容问题由 alpha.4 修复，alpha.3 本身未在该设备完成更新。没有使用远程手工部署代替软件操作。仅支持 Windows x64，程序未签名；未完整验证其他安全策略和干净机器安装。内部任务格式无法识别时要求确认，未刻意中断真实执行中任务。
