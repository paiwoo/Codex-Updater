# Codex 独立更新器

> 跨电脑交付前请先读 **交付说明.md**，其中列出运行前提、验证范围及已知的 Codex++ 启动兼容问题。此包不是首次安装器，也不保证所有 Codex++ 版本兼容。

双击 **Update-Codex.cmd**。以后更新直接运行它，无需与 Codex Agent 对话，也不用安装开发工具。

控制台每秒刷新：当前阶段（第几步）、总耗时、本阶段耗时、后台进程是否存活、上次状态更新距今多久。下载显示已收字节数和服务器提供总长度时的百分比；安装显示 Windows 实际报告的部署进度。没有真实百分比的检查、启动和等待阶段只显示耗时与活动状态，不编造进度。等待 UAC 会明确提示需要你操作。重复双击会接入正在运行的任务，不会重复安装。

请先结束其他 Codex 任务并保存工作。下载并核验安装包后，工具等待 15 秒，然后关闭本机 Codex，交给 Windows 计划任务安装，再通过 Codex++ 启动 Windows 当前注册的应用目录。关闭更新器控制台或 Codex 不会中断已经启动的 Windows 任务；Windows 用户需要保持登录，更新期间不要关机或结束该计划任务。

工具从 Codex 内置的官方稳定版发布地址动态获取版本，按数字比较 MSIX 版本；下载、签名、发布者、包身份、架构和版本核验通过后才关闭客户端。先尝试当前用户权限安装；Windows 沙箱服务需要提权时，会出现系统 UAC 提示，请使用同一 Windows 账户授权。取消授权会记录失败，并尝试重新打开已注册的客户端。不重装、不重置应用、不清理会话或浏览器缓存。`logs/backup-*` 保存更新前的 `config.toml` 和 `auth.json`，这些备份含认证信息，请勿分享。

只有以下检查全部通过，`status.json` 才写入 `complete`：Windows 注册版本达到官方当前版本；桌面进程来自这个安装目录；Codex++ 报告运行并连接相同目录；实际主窗口可访问性树完整，且两次检查均没有“有可用更新”等按钮（会遍历同进程全部窗口，避免误选空侧栏）。网络错误、无法读取窗口或仍有更新提示都会记录为失败，不会隐藏提示或伪造成功。检测不到桌面进程与检测到旧包会分别报告；旧包错误包含实际路径。

支持旧版独立 Codex++ 启动器和 1.9 统一程序。1.9 通过其内置启动 worker 启动当前 Windows 注册包，沿用原来的 Codex 用户目录和 Codex++ 状态目录。若已安装最新版但当前是原生启动、增强服务未连接，工具会重启客户端并通过 Codex++ 恢复增强服务。

双击 **Check-Codex.cmd** 可只读检查当前注册版本、实际运行目录和更新提示。错误详情见 `status.json`、`error.txt` 和 `logs/*.log`。计划任务名为 `Codex-Independent-Update`，按需运行，没有定时触发器。任务运行中再次执行会拒绝重复安装。

命令行（使用 Windows 自带的 `powershell.exe`）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Update-Codex.ps1 -CheckOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Update-Codex.ps1 -VerifyOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Update-Codex.ps1 -SelfTest
```

支持 Windows 已安装的官方稳定版 `OpenAI.Codex`（x64 / arm64）以及已安装的 Codex++。官方未来修改发布源、包签名或窗口提示文案时，需要相应更新脚本。新版本再次发布后，正常的新更新提示仍可能出现。
