# Codex Updater — Windows alpha

Independent software. Not an official OpenAI product.

Extract this entire folder into a writable local location, then open **Codex Updater.exe**. The portable build requires Microsoft Edge WebView2; use the installer if the runtime is missing. Python, Node.js, and Rust are not required to run it.

The first check is read-only. Review the repair plan, finish Codex tasks, and save your work before confirming. The tool asks Codex to quit normally and waits if it remains open. Force quit requires a separate confirmation and can interrupt active work.

During Windows deployment, keep the computer powered on and the Windows user logged in. The interface may close while the independent worker continues. Reopen it to see the result. Cancellation is available before deployment, not during Windows deployment.

This tool preserves sign-in and model configuration, and does not uninstall or reset Codex. It reports package deployment, target-version execution, and the prompt observation separately. Unknown or inaccessible results are labeled unverified.

Diagnostics stay under `%LOCALAPPDATA%\CodexUpdater`. Use the redacted export preview when sharing a problem. Do not share the entire runtime folder.

Alpha scope: Windows x64. ARM64 and macOS repair are not yet supported. Permission, policy, unsupported package types, or unavailable official packages can prevent a repair; read the reported reason rather than retrying destructively.

Copyright (c) 2026 Kabi (paiwoo). Distributed under the included MIT LICENSE.
