# Codex 更新修复

本词汇表用于区分更新提示、包安装状态与正在运行的应用，避免将不同的结果都称为“更新成功”。

## Language

**更新提示（Update Prompt）**：
Codex 界面中向用户表示存在可用更新的提示。
_Avoid_: 新版本已安装

**注册版本（Registered Version）**：
当前 Windows 用户已注册的 Codex 应用包版本。
_Avoid_: 运行版本、最新版本

**运行版本（Running Version）**：
当前实际运行的 Codex 桌面应用所属的包版本。
_Avoid_: 注册版本

**渠道提供版本（Offered Version）**：
指定发布渠道在检查时向对应平台与架构提供的 Codex 版本。
_Avoid_: 所有人都能安装的最新版

**应用显示版本（App Version）**：
客户端自身报告的版本标识，与 Windows 应用包版本可能采用不同编号。
_Avoid_: 包版本、直接作为注册版本进行比较

**更新修复（Update Repair）**：
针对 Codex 更新流程未完成或更新后仍运行旧包等异常所执行的恢复操作。
_Avoid_: 隐藏更新提示、清空用户数据

**执行中任务（Active Task）**：
Codex 正在处理或等待用户授权才能继续的一次工作。打开聊天、保留历史会话或运行桌面客户端本身不等于有执行中任务。
_Avoid_: 打开的聊天、桌面进程、会话存在

**任务空闲（Task Idle）**：
已确认 Codex 当前没有执行中任务的状态。无法确认任务状态时，不视为空闲。
_Avoid_: CPU 空闲、未检测到任务
