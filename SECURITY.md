# Security / 安全报告

## Supported versions / 支持版本

Security fixes target the latest published alpha/beta/rc or stable release and the `main` branch. Older test releases do not have a separate maintenance branch.

安全修复面向最新发布的测试版或正式版以及 `main` 分支，旧测试版没有独立维护分支。

## Report privately / 私密报告

Use [GitHub private vulnerability reporting](https://github.com/paiwoo/Codex-Updater/security/advisories/new). Include the affected version, a minimal reproduction, the impact, and relevant redacted evidence.

请通过 [GitHub 私密漏洞报告](https://github.com/paiwoo/Codex-Updater/security/advisories/new) 说明受影响版本、最小复现方式、影响和脱敏证据。

Do not put exploitable details, access tokens, authentication files, chats, personal paths, or unredacted logs in public issues. Do not test deployment or process termination on someone else's active session.

请勿将可利用细节、令牌、认证文件、聊天内容、个人路径或未脱敏日志发布到公开 Issue。不要在他人的活动会话中测试部署或进程终止。

Source validation, signature and identity checks, Windows account/session boundaries, process matching, and diagnostic redaction are security-relevant areas. Ordinary update failures without a security impact can use the [bug report form](https://github.com/paiwoo/Codex-Updater/issues/new/choose).

来源、签名与身份校验，Windows 用户和会话边界，进程识别及诊断脱敏均属于安全相关范围。普通升级故障可使用公开缺陷表单。
