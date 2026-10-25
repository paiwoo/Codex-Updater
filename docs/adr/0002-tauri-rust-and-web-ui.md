---
status: accepted
---

# 使用 Tauri、Rust 和 React 构建精致且轻量的桌面工具

2026-10-23 用户确认采用 Tauri 2 + Rust + React/TypeScript + Tailwind CSS + 定制 shadcn/ui，追求 macOS 精致应用的视觉完成度，保留 Windows 熟悉的窗口操作。Rust 负责本地更新与独立部署执行，前端负责界面与交互；现有脚本的有效部署逻辑可作为 Windows 适配素材。

选择复用系统 WebView 以减少捆绑浏览器的成本，接受运行时缺失与系统渲染差异需要显式处理的取舍。Windows 同时提供便携包与安装版，安装版处理 WebView2 缺失；不默认携带完整固定 WebView2，性能和体积由实际构建测量。首版维持 Windows，macOS 仅保留平台适配边界，不能将框架的跨平台能力当作修复功能已跨平台。
