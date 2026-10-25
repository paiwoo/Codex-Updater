[CmdletBinding()]
param(
    [switch]$Worker,
    [switch]$CheckOnly,
    [switch]$VerifyOnly,
    [switch]$SelfTest,
    [string]$WaitForRollout = '',
    [string]$WaitTurnId = '',
    [string]$TaskName = 'Codex-Independent-Update'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Appx requires Windows PowerShell 5.1, with its own module paths even when called from pwsh.
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Run with Windows powershell.exe, not pwsh.exe.' }
$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
Import-Module Appx
Add-Type -AssemblyName System.IO.Compression.FileSystem
$script:Root = $PSScriptRoot
$script:StatePath = Join-Path $Root 'status.json'
$script:State = [ordered]@{ state='starting'; message=''; time=''; workerPid=$PID; task=$TaskName }
$script:PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:FeedUrl = 'https://persistent.oaistatic.com/codex-app-prod/windows-release.json'
$script:StartedAt = Get-Date
$script:StageStartedAt = $StartedAt

function Write-State([string]$Stage, [string]$Message) {
    if ($script:State.state -ne $Stage) { $script:StageStartedAt=Get-Date }
    $script:State.state = $Stage
    $script:State.message = $Message
    $script:State.time = (Get-Date).ToString('o')
    $script:State.startedAt=$StartedAt.ToString('o')
    $script:State.stageStartedAt=$StageStartedAt.ToString('o')
    $script:State.elapsedSeconds=[int]((Get-Date)-$StartedAt).TotalSeconds
    $json = $script:State | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText("$StatePath.tmp", $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath "$StatePath.tmp" -Destination $StatePath -Force
    Write-Host "[$Stage] $Message"
}

function Format-Duration([double]$Seconds) {
    $duration=[timespan]::FromSeconds([Math]::Max(0,$Seconds))
    return '{0:00}:{1:00}:{2:00}' -f [int][Math]::Floor($duration.TotalHours),$duration.Minutes,$duration.Seconds
}

function Format-TaskProgress($Status, [bool]$Alive, [datetime]$Now=(Get-Date)) {
    $stages=@{
        checking='1/8 检查版本'; downloading='2/8 下载安装包'; validating='3/8 校验签名'
        waiting_for_reply='等待当前回复'; countdown='等待关闭客户端'; closing='4/8 关闭旧客户端'
        installing='5/8 Windows 安装'; waiting_for_uac='等待系统 UAC 授权'
        launching='6/8 启动 Codex++'; verifying='7/8 验证运行状态'; settling='8/8 复查更新提示'
        complete='完成'; failed='失败'
    }
    $stage=$stages[$Status.state]
    if (-not $stage) { $stage=$Status.state }
    $total=Format-Duration ($Now-[datetime]$Status.startedAt).TotalSeconds
    $phase=Format-Duration ($Now-[datetime]$Status.stageStartedAt).TotalSeconds
    $age=[int][Math]::Max(0,($Now-[datetime]$Status.time).TotalSeconds)
    $activity=if($Alive){'后台进程存活'}else{'后台进程已结束'}
    if ($Status.state -eq 'waiting_for_uac') { $activity='等待你允许 UAC' }
    $detail=''
    if ($Status.state -eq 'downloading') {
        $partial=Join-Path $Root 'download.partial.msix'
        if (Test-Path -LiteralPath $partial) {
            $size=(Get-Item -LiteralPath $partial).Length
            $detail=' | 已下载 {0:N1} MB' -f ($size/1MB)
            $headers=Join-Path $Root 'download-headers.txt'
            if(Test-Path -LiteralPath $headers){
                $length=Select-String -LiteralPath $headers -Pattern '^content-length:\s*(\d+)' | Select-Object -Last 1
                if($length -and [double]$length.Matches[0].Groups[1].Value -gt 0){
                    $bytes=[double]$length.Matches[0].Groups[1].Value
                    $detail+=' / {0:N1} MB ({1:N1}%)' -f ($bytes/1MB),([Math]::Min(100,100*$size/$bytes))
                }
            }
        }
    }
    if ($Status.state -eq 'installing') {
        $progressPath=Join-Path $Root 'installation-progress.json'
        if(Test-Path -LiteralPath $progressPath){
            try{
                $install=Get-Content -LiteralPath $progressPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if([datetime]$install.time -ge [datetime]$Status.stageStartedAt){
                    $detail=' | '+$install.message
                    if($install.percent -ge 0){$detail+=' ({0}%)' -f $install.percent}
                }
            }catch{}
        }
    }
    return "[$stage] 总耗时 $total | 本阶段 $phase | $activity | 状态更新于 ${age}s 前$detail"
}

function Start-CodexPlus($Package, [string]$Launcher) {
    $appPath=Join-Path $Package.InstallLocation 'app'
    $version=[version]((Get-Item -LiteralPath $Launcher).VersionInfo.ProductVersion -replace '-.*$','')
    if($version -ge [version]'1.9.0'){
        # shortcut: 1.9 removed the standalone launcher CLI; use its embedded worker until a public launch CLI exists.
        $stateDir=Join-Path $env:USERPROFILE '.codex-session-delete'
        $latest=Get-Content -LiteralPath (Join-Path $stateDir 'latest-status.json') -Raw -Encoding UTF8 -ErrorAction SilentlyContinue | ConvertFrom-Json
        $options=[ordered]@{appPath=$appPath;debugPort=9229;helperPort=57321;stateDir=$stateDir}
        if($latest.debug_port){$options.debugPort=[int]$latest.debug_port}
        if($latest.helper_port){$options.helperPort=[int]$latest.helper_port}
        $optionsPath=Join-Path $Root 'launcher-options.json'
        [IO.File]::WriteAllText($optionsPath,($options | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
        $arguments=@('--codex-plus-multi-worker',('"'+$optionsPath+'"'))
    }else{
        $arguments=@('--app-path',('"'+$appPath+'"'))
    }
    $process=Start-Process -FilePath $Launcher -ArgumentList $arguments -WindowStyle Hidden -PassThru
    $script:State.launcherPid=$process.Id
    $script:State.launcherVersion=$version.ToString()
}

function Get-Package {
    $packages = @(Get-AppxPackage -Name OpenAI.Codex)
    if ($packages.Count -ne 1) { throw 'Expected one registered OpenAI.Codex package for the current Windows user.' }
    if ($packages[0].IsDevelopmentMode -or $packages[0].Status.ToString() -ne 'Ok') {
        throw 'The registered package is not a healthy signed release. No reset or uninstall was attempted.'
    }
    return $packages[0]
}

function Get-OfficialOffer($Feed, [string]$Architecture) {
    if ($Feed.schemaVersion -ne 1 -or $Feed.packageVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw 'Unsupported official release feed.'
    }
    $candidates = @($Feed.packages | Where-Object { $_.architecture -eq $Architecture -or ($Architecture -eq 'x64' -and $_.architecture -eq 'x86_64') })
    if ($candidates.Count -ne 1) { throw 'The release feed does not contain exactly one package for this architecture.' }
    $url = [uri]$candidates[0].downloadUrl
    if ($url.Scheme -ne 'https' -or $url.Host -ne 'persistent.oaistatic.com' -or
        $url.AbsolutePath -notlike '/codex-app-prod/releases/*.msix' -or $url.UserInfo -or $url.Port -ne 443) {
        throw 'The release feed returned an unexpected download URL.'
    }
    return [pscustomobject]@{ Version=[version]$Feed.packageVersion; Url=$url.AbsoluteUri; Architecture=$Architecture }
}

function Get-Offer($Package) {
    $raw = & curl.exe --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 60 --retry 2 $FeedUrl
    if ($LASTEXITCODE -ne 0) { throw "Official update feed could not be read (curl $LASTEXITCODE)." }
    $offer=Get-OfficialOffer ($raw -join "`n" | ConvertFrom-Json) $Package.Architecture.ToString().ToLowerInvariant()
    $storeUrl='https://persistent.oaistatic.com/codex-app-prod/windows-store-update.json'
    $storeRaw=& curl.exe --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 60 --retry 2 $storeUrl
    if($LASTEXITCODE -ne 0){throw "无法核对客户端的 Store 更新清单 (curl $LASTEXITCODE)。"}
    $store=$storeRaw -join "`n" | ConvertFrom-Json
    if($store.schemaVersion -ne 1 -or $store.packageIdentity -ne 'OpenAI.Codex' -or $store.storeProductId -ne '9PLM9XGG6VKS' -or $store.buildVersion -notmatch '^\d+\.\d+\.\d+\.\d+$'){
        throw 'Store update manifest identity/version validation failed.'
    }
    if([version]$store.buildVersion -gt $offer.Version){
        $offer.Version=[version]$store.buildVersion
        $offer.Url='https://persistent.oaistatic.com/codex-app-prod/releases/'+$offer.Version+'/ChatGPT-'+$offer.Architecture+'.msix'
    }
    $manifest=Join-Path (Split-Path $Package.InstallLocation) ('OpenAI.Codex_'+$offer.Version+'_'+$offer.Architecture+'__'+$Package.PublisherId+'\AppxManifest.xml')
    $offer | Add-Member -NotePropertyName StagedManifest -NotePropertyValue $(if(Test-Path -LiteralPath $manifest -PathType Leaf){$manifest}else{''})
    return $offer
}

function Assert-StagedManifest([string]$Path,$Offer,$Installed){
    [xml]$manifest=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $id=$manifest.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Identity']")
    if($id.Name -ne 'OpenAI.Codex' -or $id.Publisher -ne $Installed.Publisher -or [version]$id.Version -ne $Offer.Version -or $id.ProcessorArchitecture -ne $Offer.Architecture){
        throw 'Windows staged package identity does not match the official update.'
    }
    $signedExe=Join-Path (Split-Path $Path) 'app\ChatGPT.exe'
    $signature=Get-AuthenticodeSignature -LiteralPath $signedExe
    $currentSignature=Get-AuthenticodeSignature -LiteralPath (Join-Path $Installed.InstallLocation 'app\ChatGPT.exe')
    if($signature.Status -ne 'Valid' -or $currentSignature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -ne $currentSignature.SignerCertificate.Subject){
        throw 'Staged executable signature/publisher validation failed.'
    }
}

function Assert-Download([string]$Path, $Offer, $Installed) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -ne $Installed.Publisher) {
        throw 'MSIX signature is invalid or its signer differs from the installed official package.'
    }
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.GetEntry('AppxManifest.xml')
        if ($null -eq $entry) { throw 'The download has no MSIX manifest.' }
        $reader = New-Object IO.StreamReader($entry.Open())
        try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $identity = $manifest.Package.Identity
        if ($identity.Name -ne 'OpenAI.Codex' -or $identity.Publisher -ne $Installed.Publisher -or
            [version]$identity.Version -ne $Offer.Version -or $identity.ProcessorArchitecture -ne $Offer.Architecture) {
            throw 'The signed package identity, version, publisher or architecture does not match.'
        }
    } finally { $zip.Dispose() }
}

function Get-Launcher {
    $paths = @()
    $paths += @(Get-Process -Name 'codex-plus-plus' -ErrorAction SilentlyContinue | ForEach-Object { $_.Path })
    $keys = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
    foreach ($item in (Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object DisplayName -eq 'Codex++')) {
        if ($item.InstallLocation) { $paths += Join-Path $item.InstallLocation 'codex-plus-plus.exe' }
    }
    $paths += Join-Path $env:LOCALAPPDATA 'Programs\Codex++\codex-plus-plus.exe'
    foreach ($path in $paths) {
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $path }
    }
    throw 'Codex++ launcher was not found. Install Codex++ before running this updater.'
}

function Get-DesktopProcesses {
    @(Get-Process -Name ChatGPT,Codex -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -match '\\WindowsApps\\OpenAI\.Codex_[^\\]+\\app\\(ChatGPT|Codex)\.exe$'
    })
}

function Get-LastTurnEvent([string]$Path) {
    $last = $null
    foreach ($line in (Select-String -LiteralPath $Path -Pattern '"type"\s*:\s*"(task_started|task_complete|turn_aborted)"' -Encoding UTF8)) {
        try { $record = $line.Line | ConvertFrom-Json } catch { continue }
        if ($record.type -eq 'event_msg' -and $record.payload.type -in @('task_started','task_complete','turn_aborted')) { $last=$record.payload }
    }
    return $last
}

function Wait-CompletedTurn {
    if (-not $WaitForRollout) {
        Write-State 'countdown' '15 秒后关闭 Codex；请结束其他任务并保存工作。'
        Start-Sleep -Seconds 15
        return
    }
    if (-not $WaitTurnId -or -not (Test-Path -LiteralPath $WaitForRollout -PathType Leaf)) { throw 'Missing completion guard parameters.' }
    Write-State 'waiting_for_reply' '安装包已准备好，等待本次回复结束；安装由独立 Windows 任务接管。'
    $deadline = (Get-Date).AddMinutes(90)
    do {
        $event = Get-LastTurnEvent $WaitForRollout
        if ($event -and $event.turn_id -ne $WaitTurnId) { throw 'A different turn started. The updater left Codex running; double-click the updater when ready.' }
        if ($event -and $event.type -eq 'turn_aborted') { throw 'The guarded turn was aborted. Codex was left running.' }
        if ($event -and $event.type -eq 'task_complete') {
            Start-Sleep -Seconds 5
            $again = Get-LastTurnEvent $WaitForRollout
            if ($again.type -eq 'task_complete' -and $again.turn_id -eq $WaitTurnId) { return }
        }
        if ((Get-Date) -gt $deadline) { throw 'Timed out waiting for the reply. Codex was left running.' }
        Start-Sleep -Seconds 2
    } while ($true)
}

function Start-IndependentTask([switch]$Test) {
    $scheduler = New-Object -ComObject Schedule.Service
    $scheduler.Connect()
    $folder = $scheduler.GetFolder('\')
    $existing = $null
    try { $existing = $folder.GetTask($TaskName) } catch { }
    if ($existing -and $existing.State -in @(2,4)) { return $existing }
    $definition = $scheduler.NewTask(0)
    $definition.RegistrationInfo.Description = 'Download, install and verify Codex independently of the Codex process tree.'
    $definition.Principal.UserId = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $definition.Principal.LogonType = 3
    $definition.Principal.RunLevel = 0
    $definition.Settings.Enabled = $true
    $definition.Settings.AllowDemandStart = $true
    $definition.Settings.DisallowStartIfOnBatteries = $false
    $definition.Settings.StopIfGoingOnBatteries = $false
    $definition.Settings.ExecutionTimeLimit = 'PT2H'
    $definition.Settings.MultipleInstances = 2
    $action = $definition.Actions.Create(0)
    $action.Path = $PowerShell
    $action.WorkingDirectory = $Root
    $action.Arguments = '-NoProfile -NonInteractive -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Worker -TaskName "' + $TaskName + '"'
    if ($Test) { $action.Arguments += ' -SelfTest' }
    if ($WaitForRollout) {
        if ($WaitForRollout.Contains('"') -or $WaitTurnId -notmatch '^[a-f0-9-]+$') { throw 'Invalid completion guard.' }
        $action.Arguments += ' -WaitForRollout "' + $WaitForRollout + '" -WaitTurnId "' + $WaitTurnId + '"'
    }
    $task = $folder.RegisterTaskDefinition($TaskName, $definition, 6, $definition.Principal.UserId, $null, 3, $null)
    $null = $task.Run($null)
    return $task
}

function Get-WindowCheck($Package) {
    $expected = Join-Path $Package.InstallLocation 'app\ChatGPT.exe'
    $app = Get-DesktopProcesses | Where-Object { $_.Path -eq $expected -and $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
    if (-not $app) { throw 'The registered package has no visible main window.' }
    $out = Join-Path $Root 'window-check.json'
    $err = Join-Path $Root 'window-check-error.txt'
    $args = '-NoProfile -NonInteractive -Sta -ExecutionPolicy Bypass -File "' + (Join-Path $Root 'Inspect-CodexWindow.ps1') + '" -AppProcessId ' + $app.Id
    $probe = Start-Process -FilePath $PowerShell -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    $null=$probe.Handle
    if (-not $probe.WaitForExit(45000)) { $probe.Kill(); throw 'Window accessibility verification timed out.' }
    $probe.WaitForExit()
    if ($probe.ExitCode -ne 0) { throw 'Window accessibility verification failed; see window-check-error.txt.' }
    $check = Get-Content -LiteralPath $out -Encoding UTF8 -Raw | ConvertFrom-Json
    if (-not $check.accessible) { throw 'The window accessibility tree is incomplete; update prompt absence is unverified.' }
    return $check
}

function Assert-LaunchedPackage($Package, $Offer) {
    if ([version]$Package.Version -lt $Offer.Version) { throw 'The registered package is behind the current official feed.' }
    $expected = Join-Path $Package.InstallLocation 'app\ChatGPT.exe'
    $running = @(Get-DesktopProcesses)
    $script:State.runningProcesses=@($running | Select-Object Id,Path)
    if ($running.Count -eq 0) { throw '未检测到 Codex 桌面进程；正在等待 Codex++ 真正启动客户端。' }
    if (@($running | Where-Object Path -ne $expected).Count -gt 0) {
        $paths=@($running | Select-Object -ExpandProperty Path -Unique) -join '; '
        throw "运行包与注册包不同。应运行：$expected；实际：$paths"
    }
    $script:State.runningPath = $expected
    $check = Get-WindowCheck $Package
    $script:State.windowCheck = $check
    if ($check.updatePromptVisible) { throw 'Codex still displays an update prompt. This run is not marked successful.' }
}

function Assert-PlusStatus($Package) {
    $plusPath=Join-Path $env:USERPROFILE '.codex-session-delete\latest-status.json'
    $plus=Get-Content -LiteralPath $plusPath -Encoding UTF8 -Raw | ConvertFrom-Json
    if ($plus.codex_app.TrimEnd('\') -ne (Join-Path $Package.InstallLocation 'app') -or $plus.status -ne 'running') {
        throw 'Codex++ did not report running against the newly registered app directory.'
    }
    $script:State.codexPlusPlusStatus=$plus.status
}

function Invoke-SelfTest {
    if((Format-Duration 3661) -ne '01:01:01'){throw 'Elapsed-time formatting failed.'}
    $sample=[pscustomobject]@{state='checking';startedAt='2026-01-01T00:00:00+08:00';stageStartedAt='2026-01-01T00:01:00+08:00';time='2026-01-01T00:01:10+08:00'}
    $line=Format-TaskProgress $sample $true ([datetime]'2026-01-01T00:01:15+08:00')
    if($line -notmatch '1/8' -or $line -notmatch '00:01:15' -or $line -notmatch '00:00:15' -or $line -notmatch '5s' -or $line -notmatch '存活'){throw 'Live progress/time self-check failed.'}
    if ([version]'26.1007.9446.0' -le [version]'26.1007.2314.0' -or [version]'26.999.1.0' -ge [version]'26.1000.1.0') { throw 'Numeric version comparison failed.' }
    $feed = @{schemaVersion=1;packageVersion='26.1007.9446.0';packages=@(@{architecture='x64';downloadUrl='https://persistent.oaistatic.com/codex-app-prod/releases/26.1007.9446.0/ChatGPT-x64.msix'})}
    $offer = Get-OfficialOffer $feed 'x64'
    if ($offer.Version -ne [version]'26.1007.9446.0') { throw 'Feed parse failed.' }
    foreach ($bad in @('https://evil.example/test.msix','http://persistent.oaistatic.com/codex-app-prod/releases/a.msix','https://persistent.oaistatic.com/other/a.msix')) {
        $feed.packages[0].downloadUrl=$bad
        $rejected=$false
        try { $null = Get-OfficialOffer $feed 'x64' } catch { $rejected=$true }
        if (-not $rejected) { throw 'Unsafe feed URL was accepted.' }
    }
    $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
    $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($parent.ParentProcessId)"
    $proof = [ordered]@{ passed=$true; checks=@('feed-validation','numeric-version','elapsed-time','live-progress'); pid=$PID; parent=$parent.Name; time=(Get-Date).ToString('o'); worker=[bool]$Worker }
    if ($Worker) {
        if ($parent.Name -match '^(ChatGPT|codex|codex-plus-plus)\.exe$') { throw 'Self-test task is still inside the client process tree.' }
        $proof | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Root 'task-self-test.json') -Encoding UTF8
    }
    $proof | ConvertTo-Json
}

if ($SelfTest) { Invoke-SelfTest; return }
if ($CheckOnly -or $VerifyOnly) {
    $package = Get-Package
    $offer = Get-Offer $package
    $result = [ordered]@{installedVersion=$package.Version.ToString();latestOfferedVersion=$offer.Version.ToString();updateAvailable=([version]$package.Version -lt $offer.Version);installLocation=$package.InstallLocation;launcher=(Get-Launcher)}
    if ($VerifyOnly) {
        Assert-LaunchedPackage $package $offer
        Assert-PlusStatus $package
        $result.runningPath=$State.runningPath
        $result.windowCheck=$State.windowCheck
        $result.codexPlusPlusStatus=$State.codexPlusPlusStatus
    }
    $result | ConvertTo-Json -Depth 5
    return
}
if (-not $Worker) {
    $requestedAt=(Get-Date).AddSeconds(-1)
    $task = Start-IndependentTask
    Write-Host '已启动独立 Windows 更新任务。安装时会关闭并重新启动 Codex，请先结束其他任务。'
    Write-Host "结果文件：$StatePath"
    if ($WaitForRollout) { return }
    $startDeadline=(Get-Date).AddSeconds(30)
    while ($task.State -notin @(2,4) -and $task.LastRunTime -lt $requestedAt) {
        if ((Get-Date) -gt $startDeadline) { throw 'Windows did not start the independent update task within 30 seconds.' }
        Start-Sleep -Milliseconds 500
    }
    $lastMessage=''
    $previousLineLength=0
    while ($task.State -in @(2,4)) {
        if (Test-Path -LiteralPath $StatePath) {
            try {
                $s=Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
                $message="[$($s.state)] $($s.message)"
                if ($message -ne $lastMessage) {
                    Write-Host ''
                    Write-Host $message
                    $lastMessage=$message
                    $previousLineLength=0
                }
                $alive=$null -ne (Get-Process -Id $s.workerPid -ErrorAction SilentlyContinue)
                $line=Format-TaskProgress $s $alive
                Write-Host -NoNewline ("`r"+$line.PadRight($previousLineLength))
                $previousLineLength=$line.Length
            } catch { }
        }
        Start-Sleep -Seconds 1
    }
    Write-Host ''
    $result=Get-Content -LiteralPath $StatePath -Encoding UTF8 -Raw | ConvertFrom-Json
    Write-Host (Format-TaskProgress $result $false ([datetime]$result.time))
    Write-Host $result.message
    if ($task.LastTaskResult -ne 0 -or $result.state -ne 'complete') {
        Write-Host "失败阶段：$($result.failedStage)。详情：$StatePath" -ForegroundColor Red
        exit 1
    }
    Write-Host "已验证版本：$($result.installedVersion)。详情：$StatePath" -ForegroundColor Green
    return
}

$mutex = New-Object Threading.Mutex($false, ('Local\CodexIndependentUpdater-' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$locked = $false
$closedClient = $false
$launcher = $null
try {
    try { $locked=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked=$true }
    if (-not $locked) { throw 'Another update worker is already running.' }
    $logs = Join-Path $Root 'logs'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null
    Start-Transcript -Path (Join-Path $logs ((Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')) -Force | Out-Null
    $self = Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
    $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($self.ParentProcessId)"
    $State.workerParent=$parent.Name
    if ($parent.Name -match '^(ChatGPT|codex|codex-plus-plus)\.exe$') { throw 'Use the launcher so Windows Task Scheduler owns the installer.' }
    Write-State 'checking' '检查 Windows 注册版本和官方发布源。'
    $installed = Get-Package
    $State.beforeVersion=$installed.Version.ToString()
    $offer = Get-Offer $installed
    $State.targetVersion=$offer.Version.ToString()
    $launcher = Get-Launcher
    $State.launcher=$launcher
    if ([version]$installed.Version -lt $offer.Version) {
        $cache = Join-Path $Root ('ChatGPT-' + $offer.Version + '-' + $offer.Architecture + '.msix')
        $register=$false
        if($offer.StagedManifest){
            Write-State 'validating' 'Windows 已下载并暂存较新包，核验身份及签名后由独立任务完成注册。'
            $cache=$offer.StagedManifest
            $register=$true
            Assert-StagedManifest $cache $offer $installed
        } elseif (Test-Path -LiteralPath $cache) {
            Write-State 'validating' '核验缓存安装包的数字签名、身份、版本和架构。'
            try { Assert-Download $cache $offer $installed } catch { throw 'Cached MSIX failed validation. Remove only that file, then retry.' }
        } else {
            Write-State 'downloading' '下载官方签名安装包；下载完成前不会关闭 Codex。'
            $partial = Join-Path $Root 'download.partial.msix'
            & curl.exe --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 30 --max-time 1800 --retry 2 --dump-header (Join-Path $Root 'download-headers.txt') --output $partial $offer.Url
            if ($LASTEXITCODE -ne 0) { throw "Official MSIX download failed (curl $LASTEXITCODE). Codex was left running." }
            Write-State 'validating' '下载完成，核验数字签名、身份、版本和架构。'
            Assert-Download $partial $offer $installed
            Move-Item -LiteralPath $partial -Destination $cache -Force
        }
        $State.packageSha256=(Get-FileHash -LiteralPath $cache -Algorithm SHA256).Hash
        Wait-CompletedTurn
        # Re-read registration before closing: another updater may have completed during download.
        $installed = Get-Package
        if ([version]$installed.Version -lt $offer.Version) {
            if($register){Assert-StagedManifest $cache $offer $installed}else{Assert-Download $cache $offer $installed}
            $backup = Join-Path $logs ('backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
            New-Item -ItemType Directory -Path $backup | Out-Null
            $homePath = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
            foreach ($name in @('config.toml','auth.json')) {
                $path = Join-Path $homePath $name
                if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination (Join-Path $backup $name) }
            }
            $State.backup=$backup
            Write-State 'closing' '关闭本机 Codex 和旧 Codex++ 启动器，独立安装任务继续运行。'
            $closedClient=$true
            foreach ($app in (Get-DesktopProcesses | Where-Object MainWindowHandle -ne ([IntPtr]::Zero))) { $null=$app.CloseMainWindow() }
            $deadline=(Get-Date).AddSeconds(12)
            while ((Get-DesktopProcesses).Count -gt 0 -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
            Get-DesktopProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
            Get-Process -Name 'codex-plus-plus' -ErrorAction SilentlyContinue | Where-Object Path -eq $launcher | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            if ((Get-DesktopProcesses).Count -gt 0) { throw 'Codex is still running. No package change was attempted.' }
            Write-State 'installing' '由 Windows 安装并注册官方 MSIX 包。'
            $installArgs='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + (Join-Path $Root 'Install-CodexPackage.ps1') + '" -PackagePath "' + $cache + '" -ExpectedVersion "' + $offer.Version + '" -ExpectedSid "' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value + '"'
            if($register){$installArgs+=' -Register'}
            $installer=Start-Process -FilePath $PowerShell -ArgumentList $installArgs -WindowStyle Hidden -Wait -PassThru
            if($installer.ExitCode -ne 0){
                $installResult=Get-Content -LiteralPath (Join-Path $Root 'installation.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                if(-not $installResult.needsElevation){throw $installResult.message}
                Write-State 'waiting_for_uac' 'Windows 服务更新需要管理员授权，请在系统 UAC 提示中允许安装。'
                $installer=Start-Process -FilePath $PowerShell -ArgumentList $installArgs -Verb RunAs -WindowStyle Hidden -PassThru
                $null=$installer.Handle
                Write-State 'installing' '管理员已授权，Windows 正在部署安装包。'
                $installer.WaitForExit()
                if ($installer.ExitCode -ne 0) { throw 'Elevated installation failed. See installation.json for the Windows error.' }
            }
            $installed = Get-Package
            if ([version]$installed.Version -lt $offer.Version) { throw 'Windows did not register the downloaded package version.' }
            $State.installedVersion=$installed.Version.ToString()
        }
    }
    $installed=Get-Package
    $plusReady=$false
    try { Assert-PlusStatus $installed; $plusReady=$true } catch { }
    if (-not $plusReady -or -not (Get-DesktopProcesses | Where-Object { $_.Path -eq (Join-Path $installed.InstallLocation 'app\ChatGPT.exe') })) {
        if(@(Get-DesktopProcesses).Count -gt 0){
            Wait-CompletedTurn
            Write-State 'closing' '客户端已是新版本，重新通过 Codex++ 启动以恢复增强服务。'
            $closedClient=$true
            Get-DesktopProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        Write-State 'launching' '通过 Codex++ 明确启动 Windows 当前注册的新包。'
        # A fresh Windows task inherits persistent user environment instead of the old client's snapshot.
        foreach ($entry in [Environment]::GetEnvironmentVariables('User').GetEnumerator()) {
            if ($entry.Key -ne 'Path') { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
        }
        Start-CodexPlus $installed $launcher
    }
    Write-State 'verifying' '核对新包运行路径、Codex++ 状态及窗口更新提示。'
    $deadline=(Get-Date).AddMinutes(3)
    do {
        Start-Sleep -Seconds 5
        $lastError=$null
        try { Assert-LaunchedPackage $installed $offer; Assert-PlusStatus $installed } catch {
            $lastError=$_.Exception.Message
            Write-State 'verifying' $lastError
        }
        if (-not $lastError) { break }
    } while ((Get-Date) -lt $deadline)
    if ($lastError) { throw $lastError }
    # Allow the new client's first background update check to settle before declaring success.
    Write-State 'settling' '首次验证通过，等待 30 秒后台更新检查后再次核对。'
    Start-Sleep -Seconds 30
    $currentOffer=Get-Offer $installed
    Assert-LaunchedPackage $installed $currentOffer
    Assert-PlusStatus $installed
    $State.installedVersion=$installed.Version.ToString()
    $State.latestOfferedVersion=$currentOffer.Version.ToString()
    Write-State 'complete' '更新已验证：Windows 注册包与运行路径一致，Codex++ 已连接，窗口未显示更新提示。'
} catch {
    if ($locked) {
        $failureMessage=$_.Exception.Message
        $State.failedStage=$State.state
        if ($closedClient -and $launcher -and -not (Get-DesktopProcesses)) {
            try {
                $registered=Get-Package
                Start-CodexPlus $registered $launcher
                $State.recoveryLaunchAttempted=$true
            } catch { $State.recoveryLaunchAttempted=$false }
        }
        Write-State 'failed' $failureMessage
        $_ | Out-String | Set-Content -LiteralPath (Join-Path $Root 'error.txt') -Encoding UTF8
    }
    exit 1
} finally {
    if ($locked) { try { Stop-Transcript | Out-Null } catch { }; $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
