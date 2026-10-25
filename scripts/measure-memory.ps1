param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class MemoryProbeWindow {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
'@
function Get-AppMemory([int]$RootId) {
    $all = Get-CimInstance Win32_Process
    $ids = @($RootId)
    do {
        $next = @($all | Where-Object { $_.ParentProcessId -in $ids -and $_.ProcessId -notin $ids } | Select-Object -ExpandProperty ProcessId)
        $ids += $next
    } while ($next.Count -gt 0)
    $processes = @(Get-Process -Id $ids -ErrorAction SilentlyContinue)
    @{
        processCount = $processes.Count
        privateBytes = ($processes | Measure-Object PrivateMemorySize64 -Sum).Sum
        workingSetBytes = ($processes | Measure-Object WorkingSet64 -Sum).Sum
    }
}
$exe = (Resolve-Path -LiteralPath $Executable).Path
$app = Start-Process -FilePath $exe -PassThru -WindowStyle Hidden
try {
    for ($i = 0; $i -lt 50; $i++) {
        Start-Sleep -Milliseconds 200
        $app.Refresh()
        if ($app.HasExited) { throw 'Test application exited early' }
        if ($app.MainWindowHandle -ne [IntPtr]::Zero) { break }
    }
    if ($app.MainWindowHandle -eq [IntPtr]::Zero) { throw 'Test application has no window' }
    [void][MemoryProbeWindow]::ShowWindow($app.MainWindowHandle, 9)
    [void][MemoryProbeWindow]::SetForegroundWindow($app.MainWindowHandle)
    Start-Sleep -Seconds 45
    $foreground = Get-AppMemory $app.Id
    $foreground.focused = [MemoryProbeWindow]::GetForegroundWindow() -eq $app.MainWindowHandle
    [void][MemoryProbeWindow]::ShowWindow($app.MainWindowHandle, 6)
    Start-Sleep -Seconds 30
    $background = Get-AppMemory $app.Id
    $report = @{
        executable = $exe
        measuredAt = (Get-Date).ToString('o')
        debugInterface = $false
        foregroundAfterSeconds = 45
        minimizedAfterSeconds = 30
        foreground = $foreground
        minimized = $background
    }
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
    [void](New-Item -ItemType Directory -Force -Path $parent)
    $report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 4
    if ($foreground.privateBytes -le 0 -or $background.privateBytes -le 0) { throw 'Invalid process memory measurement' }
} finally {
    $app.Refresh()
    if (!$app.HasExited) {
        [void]$app.CloseMainWindow()
        if (!$app.WaitForExit(3000)) { $app.Kill() }
    }
}
