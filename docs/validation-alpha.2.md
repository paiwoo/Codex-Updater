# 0.1.0-alpha.2 validation / 验证记录

Date / 日期：2026-10-26（Asia/Shanghai）。Windows x64 Alpha。

## Verified / 已验证

| Check / 检查                                      | Result / 结果                                                                                                   |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| TypeScript + Vite production build / 前端生产构建 | Passed / 通过                                                                                                   |
| Vitest                                            | 6 passed / 6 项通过                                                                                             |
| UI flows / 界面流程                               | 21 passed, including active/unknown task confirmation / 21 项通过，含任务执行中与未知状态确认                   |
| Rust                                              | 20 passed, including old-run compatibility / 20 项通过，含历史记录兼容                                          |
| Windows activity safety checks / 任务检测安全检查 | Active, idle, unknown, partial writes, stale locks, bounded reads, force confirmation, new-turn race / 全部通过 |
| PowerShell syntax and formatting / 脚本语法与格式 | Passed / 通过                                                                                                   |
| Native read-only smoke / 原生只读联调             | No page errors; installed and offered versions agree / 页面错误为 0，注册版本与官方源一致                       |
| Third-party notices / 第三方许可                  | 333 locked graph entries, no missing text / 333 项，无缺失文本                                                  |
| ZIP + NSIS + SHA-256 / 发布产物                   | Built and checked / 已构建并核对                                                                                |

## Real occupancy failure / 真实占用故障

A second Windows 10 Pro 22H2 x64 machine had `26.1016.8622.0` registered and `26.1021.3705.0` staged. Deployment failed with `0x80073D02`; the Windows deployment log identified an active `OpenAI.Codex` app service.

The original process-exit approach was reproduced: even after idle Codex and its associated copied app-server had exited, deployment and one retry still failed. The fixed deployment operation, after repeating the idle check and official package validation, used Windows `ForceTargetApplicationShutdown`. Registration succeeded, Codex was launched, and every detected desktop process ran from the `26.1021.3705.0` package directory. The copied app-server runtime changed to the new runtime as well.

另一台 Windows 10 Pro 22H2 x64 设备中，旧包已注册、新包已暂存。复现了进程结束后，Windows 仍因旧包活动服务拒绝更新的情况。重复空闲检测与官方包校验后，使用 Windows 的目标包关闭选项完成同包注册；随后启动 Codex，确认桌面进程均来自目标新包。没有通过卸载、重置、修改认证或提权来完成修复。

This validates the fixed Windows operation against a real retained-service failure. It does not claim every failure mode has been tested on hardware. Active/unknown task choices and the new-turn race use controlled fixtures; a real executing task was not deliberately interrupted.

## Release files / 发布文件

| File / 文件               | Bytes / 字节数 |
| ------------------------- | -------------: |
| Portable ZIP / 便携包     |        2388277 |
| NSIS installer / 安装程序 |        1987431 |

```text
9309d4395973245c0b65f4d0e8506eda2fe4e99371f34c3fb3d36e8c98459ef1  Codex-Updater_0.1.0-alpha.2_windows-x64_portable.zip
07bea01ccc7acbce2024fad93c6d2662b8c43972327d5807b6060a60c6e9abf1  Codex-Updater_0.1.0-alpha.2_windows-x64_setup.exe
```

## Limits / 限制

The remote desktop MCP was unavailable in the working session. Remote checks used SSH, Windows deployment logs, and scheduled tasks in the existing interactive account. No remote screenshot or visual confirmation of Codex's update prompt is claimed.

远端桌面 MCP 未加载，实机验证使用 SSH、部署日志及现有账号的交互会话计划任务；没有远端画面或更新提示的目视验证。会话检测依赖 Codex 内部生命周期格式，无法识别时会要求确认。干净机器安装、缺失 WebView2、其他 Windows 或企业策略环境、ARM64、macOS 尚未完整验证。程序未代码签名，本次未重新测量内存。
