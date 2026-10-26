param([string]$ProcessHelper)
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
    & {
        $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-CodexOccupants'},$true)
        . ([scriptblock]::Create($definition.Extent.Text))
        $SessionId=7;$ExpectedSid='fixture-owner'
        $helper=Join-Path $root 'process-helper.ps1'
        $inputData=@{processHelper=$helper}
        $bin=Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin\runtime\codex.exe'
        $fixtures=@(
            [pscustomobject]@{Id=10;SessionId=7;Path='C:\WindowsApps\Codex\ChatGPT.exe'},
            [pscustomobject]@{Id=11;SessionId=7;Path='C:\Windows\foreign-owner.exe'},
            [pscustomobject]@{Id=12;SessionId=8;Path='C:\Windows\other-session.exe'},
            [pscustomobject]@{Id=13;SessionId=7;Path='C:\Windows\unrelated.exe'},
            [pscustomobject]@{Id=14;SessionId=7;Path=$helper},
            [pscustomobject]@{Id=$PID;SessionId=7;Path='C:\Windows\powershell.exe'},
            [pscustomobject]@{Id=20;SessionId=7;Path=$bin}
        )
        function Get-CodexProcesses($Package){return @($fixtures[0])}
        function Get-Process($Name){if($Name){return @($fixtures[-1])};return $fixtures}
        function Get-CimInstance($ClassName,$Filter){
            $id=[int]($Filter -replace '^ProcessId=','')
            return [pscustomobject]@{ProcessId=$id;ParentProcessId=$(if($id -eq 20){10}else{0})}
        }
        function Invoke-CimMethod($InputObject,$MethodName){return @{ReturnValue=0;Sid=$(if($InputObject.ProcessId -eq 11){'other-owner'}else{$ExpectedSid})}}
        [IO.File]::WriteAllText($helper,('Write-Output ''[10,11,12,14,'+$PID+']''; $global:LASTEXITCODE=0'))
        $ids=@(Get-CodexOccupants ([pscustomobject]@{Name='fixture'}) | ForEach-Object Id | Sort-Object)
        Assert (($ids -join ',') -eq '10,20') 'Only same-user/session package processes and their associated app-server may be selected; exclude updater and probe'
        foreach($result in @('Write-Output ''invalid''; $global:LASTEXITCODE=0','Write-Output ''[]''; $global:LASTEXITCODE=1')){
            [IO.File]::WriteAllText($helper,$result)
            $rejected=$false
            try{$null=Get-CodexOccupants ([pscustomobject]@{Name='fixture'})}catch{$rejected=$true}
            Assert $rejected 'Missing or invalid native query results must prevent shutdown'
        }
        if($ProcessHelper){
            $inputData.processHelper=(Resolve-Path -LiteralPath $ProcessHelper).Path
            $ids=@(Get-CodexOccupants ([pscustomobject]@{Name='fixture'}) | ForEach-Object Id | Sort-Object)
            Assert (($ids -join ',') -eq '10,20') 'The built GUI helper must return and drain its JSON output before PowerShell continues'
        }
    }
    Write-Output 'Activity checks passed: task states, confirmation, stale locks, bounded reads, new-turn race, native-query failure, account/session scope, app-server, self-protection.'
}finally{
    $env:CODEX_HOME=$previousCodexRoot
    $resolved=[IO.Path]::GetFullPath($root)
    $temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($temporary,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture cleanup path'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
