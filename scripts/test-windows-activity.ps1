$ErrorActionPreference='Stop'
$source=Join-Path (Split-Path $PSScriptRoot) 'src-tauri\scripts\windows.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
foreach($name in @('Get-CodexTaskMarker','Get-CodexActivity','Stop-CodexForUpdate')){
    $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    . ([scriptblock]::Create($definition.Extent.Text))
}
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
# Fixtures never call native process inspection, deployment or termination.
function Get-CodexOccupants($Package){return @($script:fakeProcess)}
$script:killed=0
$script:fakeProcess=[pscustomobject]@{HasExited=$false}
$script:fakeProcess | Add-Member ScriptMethod Kill {$script:killed++}
$root=Join-Path ([IO.Path]::GetTempPath()) ('codex-updater-activity-'+[guid]::NewGuid().ToString('N'))
$previousCodexRoot=$env:CODEX_HOME
try{
    $env:CODEX_HOME=$root
    $locks=New-Item -ItemType Directory -Path (Join-Path $root 'thread-writer-locks')
    $sessions=New-Item -ItemType Directory -Path (Join-Path $root 'sessions')
    $id='00000000-0000-0000-0000-000000000001'
    $rollout=Join-Path $sessions.FullName "rollout-$id.jsonl"
    $lock=Join-Path $locks.FullName "$id.lock"
    [IO.File]::WriteAllText($lock,'')
    $held=[IO.File]::Open($lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{
        [IO.File]::WriteAllText($rollout,'{"type":"event_msg","payload":{"type":"task_started"}}'+"`n")
        Assert ((Get-CodexActivity $null) -eq 'active') 'A live executing task must be active'
        $result=Stop-CodexForUpdate $null $false
        Assert ($result.activity -eq 'active' -and $script:killed -eq 0) 'Active tasks must never be auto-terminated'
        [IO.File]::AppendAllText($rollout,'{"type":"event_msg","payload":{"type":"task_complete"}}'+"`n")
        Assert ((Get-CodexActivity $null) -eq 'idle') 'A live completed task must be idle'
        $null=Stop-CodexForUpdate $null $false
        Assert ($script:killed -eq 1) 'Confirmed idle processes must close without a prompt'
        [IO.File]::AppendAllText($rollout,'{"type":"event_msg","payload":')
        Assert ((Get-CodexActivity $null) -eq 'unknown') 'Partial writes must not be treated as idle'
        $null=Stop-CodexForUpdate $null $false
        Assert ($script:killed -eq 1) 'Unknown tasks must stay open'
        $null=Stop-CodexForUpdate $null $true
        Assert ($script:killed -eq 2) 'Explicit force quit must allow continuation'
        [IO.File]::WriteAllText($rollout,('x'* (4MB+100))+"`n"+'{"type":"event_msg","payload":{"type":"task_complete"}}'+"`n")
        Assert ((Get-CodexTaskMarker $rollout) -eq 'idle') 'Bounded tail reads must find the latest complete marker'
    }finally{$held.Dispose()}
    Assert ((Get-CodexActivity $null) -eq 'unknown') 'Stale unlocked files must not prove that an engine is idle'
    $script:activityChecks=0
    function Get-CodexActivity($Package){$script:activityChecks++;if($script:activityChecks -eq 1){return 'idle'};return 'active'}
    $null=Stop-CodexForUpdate $null $false
    Assert ($script:killed -eq 2) 'A task starting between checks must prevent automatic termination'
    Write-Output 'Activity checks passed: active, idle, unknown, confirmation, stale locks, bounded reads, new-turn race.'
}finally{
    $env:CODEX_HOME=$previousCodexRoot
    $resolved=[IO.Path]::GetFullPath($root)
    $temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($temporary,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture cleanup path'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
