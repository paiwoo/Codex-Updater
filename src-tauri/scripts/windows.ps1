param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Identity','Inspect','Staged','Validate','Activity','Quit','ForceQuit','Deploy','Launch','Prompt','Events')]
    [string]$Operation,
    [Parameter(Mandatory=$true)][string]$InputPath
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$env:PSModulePath="$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
$ExpectedFamily='OpenAI.Codex_2p2nqsd0c76g0'
$ExpectedPublisher='CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B'
$ExpectedSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$SessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId
$inputData=Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Get-CodexPackage {
    $packages=@(Get-AppxPackage -Name OpenAI.Codex)
    if($packages.Count -eq 0){return $null}
    if($packages.Count -ne 1){throw 'Expected one current-user Codex package.'}
    $p=$packages[0]
    if($p.PackageFamilyName -ne $ExpectedFamily -or $p.Publisher -ne $ExpectedPublisher -or $p.IsDevelopmentMode){throw 'Unsupported Codex package identity or development installation.'}
    return $p
}
function Get-CodexProcesses($Package) {
    if(-not $Package){return @()}
    $packageParent=[IO.Path]::GetFullPath((Split-Path $Package.InstallLocation)).TrimEnd('\')+'\'
    $out=@()
    foreach($p in @(Get-Process -Name ChatGPT,Codex -ErrorAction SilentlyContinue)){
        try{
            if($p.SessionId -ne $SessionId){continue}
            if(-not $p.Path){throw 'Cannot inspect a desktop process in this session.'}
            $full=[IO.Path]::GetFullPath($p.Path)
            if(-not $full.StartsWith($packageParent,[StringComparison]::OrdinalIgnoreCase)){continue}
            $relative=$full.Substring($packageParent.Length)
            if($relative -notmatch '^OpenAI\.Codex_\d+\.\d+\.\d+\.\d+_(x64|arm64)__2p2nqsd0c76g0\\app\\(ChatGPT|Codex)\.exe$'){continue}
            $cim=Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)"
            $owner=Invoke-CimMethod -InputObject $cim -MethodName GetOwnerSid
            if($owner.ReturnValue -ne 0){throw 'Cannot verify a desktop process owner.'}
            if($owner.Sid -ne $ExpectedSid){continue}
            $out+= $p
        }catch{
            if(Get-Process -Id $p.Id -ErrorAction SilentlyContinue){throw}
        }
    }
    return @($out)
}
function Get-CodexOccupants($Package){
    if(-not $Package){return @()}
    if(-not ('CodexUpdater.PackageIdentity' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace CodexUpdater {
    public class PackageIdentity {
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
        public static extern int GetPackageFamilyName(IntPtr process, ref int length, StringBuilder name);
    }
}
'@
    }
    $desktop=@(Get-CodexProcesses $Package)
    $out=@{}
    foreach($p in $desktop){$out[$p.Id]=$p}
    foreach($p in @(Get-Process | Where-Object SessionId -eq $SessionId)){
        try{
            $length=512;$family=New-Object Text.StringBuilder 512
            $result=[CodexUpdater.PackageIdentity]::GetPackageFamilyName($p.Handle,[ref]$length,$family)
            if($result -ne 0 -or $family.ToString() -ne $ExpectedFamily){continue}
        }catch{
            if($out.ContainsKey($p.Id) -and (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)){throw}
            continue
        }
        $cim=Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)"
        if(-not $cim){continue}
        $owner=Invoke-CimMethod -InputObject $cim -MethodName GetOwnerSid
        if($owner.ReturnValue -ne 0){throw 'Cannot verify a package process owner.'}
        if($owner.Sid -eq $ExpectedSid){$out[$p.Id]=$p}
    }
    # The copied app-server can be outside WindowsApps and have no package identity.
    $bin=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin')).TrimEnd('\')+'\'
    foreach($p in @(Get-Process -Name codex -ErrorAction SilentlyContinue)){
        if($p.SessionId -ne $SessionId -or -not $p.Path -or -not $p.Path.StartsWith($bin,[StringComparison]::OrdinalIgnoreCase)){continue}
        $cim=Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)"
        if(-not $cim -or -not $out.ContainsKey([int]$cim.ParentProcessId)){continue}
        $owner=Invoke-CimMethod -InputObject $cim -MethodName GetOwnerSid
        if($owner.ReturnValue -ne 0){throw 'Cannot verify the app-server owner.'}
        if($owner.Sid -eq $ExpectedSid){$out[$p.Id]=$p}
    }
    return @($out.Values)
}
function Get-CodexTaskMarker([string]$Path){
    # shortcut: internal task markers may change; unrecognized or truncated data requires confirmation.
    $stream=$null
    try{
        $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        $limit=4MB;$offset=[Math]::Max(0,$stream.Length-$limit)
        $null=$stream.Seek($offset,[IO.SeekOrigin]::Begin)
        $reader=New-Object IO.StreamReader($stream,(New-Object Text.UTF8Encoding($false,$true)))
        try{
            if($offset -gt 0){$null=$reader.ReadLine()}
            $state='unknown'
            while(-not $reader.EndOfStream){
                $line=$reader.ReadLine()
                try{$item=$line | ConvertFrom-Json}catch{return 'unknown'}
                if($item.type -ne 'event_msg'){continue}
                switch($item.payload.type){
                    'task_started' {$state='active'}
                    'task_complete' {$state='idle'}
                    'turn_aborted' {$state='idle'}
                }
            }
            return $state
        }finally{$reader.Dispose()}
    }catch{return 'unknown'}finally{if($stream){$stream.Dispose()}}
}
function Get-CodexActivity($Package){
    try{
    if(@(Get-CodexOccupants $Package).Count -eq 0){return 'idle'}
    $codexRoot=if($env:CODEX_HOME){$env:CODEX_HOME}else{Join-Path $env:USERPROFILE '.codex'}
    $locks=Join-Path $codexRoot 'thread-writer-locks'
    if(-not (Test-Path -LiteralPath $locks -PathType Container)){return 'unknown'}
    $seen=0;$unknown=$false
    foreach($file in @(Get-ChildItem -LiteralPath $locks -Filter '*.lock' -File)){
        if($file.Name -eq '.coordination.lock'){continue}
        if($file.BaseName -notmatch '^[0-9a-fA-F-]{36}$'){return 'unknown'}
        try{
            $handle=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
            $handle.Dispose();continue
        }catch [IO.IOException]{}catch{return 'unknown'}
        $seen++
        $matches=@(Get-ChildItem -LiteralPath (Join-Path $codexRoot 'sessions') -Recurse -File -Filter "*$($file.BaseName).jsonl")
        if($matches.Count -ne 1){$unknown=$true;continue}
        $state=Get-CodexTaskMarker $matches[0].FullName
        if($state -eq 'active'){return 'active'}
        if($state -ne 'idle'){$unknown=$true}
    }
    # An engine without observable live sessions may use a different CODEX_HOME.
    if($seen -eq 0 -or $unknown){return 'unknown'}
    return 'idle'
    }catch{return 'unknown'}
}
function Stop-CodexForUpdate($Package,[bool]$Confirmed){
    $activity=Get-CodexActivity $Package
    if(-not $Confirmed -and $activity -ne 'idle'){return @{activity=$activity;remaining=@(Get-CodexOccupants $Package).Count}}
    $processes=@(Get-CodexOccupants $Package)
    # Recheck immediately before terminating; a new turn may have started during inspection.
    if(-not $Confirmed){
        $activity=Get-CodexActivity $Package
        if($activity -ne 'idle'){return @{activity=$activity;remaining=$processes.Count}}
    }
    foreach($process in $processes){
        try{if(-not $process.HasExited){$process.Kill()}}catch{if(-not $process.HasExited){throw}}
    }
    return @{activity=$activity;remaining=@(Get-CodexOccupants $Package).Count}
}
function Get-AppEntry($Package){
    [xml]$manifest=Get-Content -LiteralPath (Join-Path $Package.InstallLocation 'AppxManifest.xml') -Raw -Encoding UTF8
    $app=@($manifest.Package.Applications.Application | Where-Object Id -eq 'App')
    if($app.Count -ne 1 -or $app[0].Executable -notmatch '^app[/\\](ChatGPT|Codex)\.exe$'){throw 'Unsupported desktop application entry.'}
    return $app[0]
}
function Get-StagedPath($Package,[string]$Version){
    if($Version -notmatch '^\d+\.\d+\.\d+\.\d+$'){throw 'Invalid target version.'}
    $root=Join-Path (Split-Path $Package.InstallLocation) ('OpenAI.Codex_'+$Version+'_'+$Package.Architecture.ToString().ToLowerInvariant()+'__'+$Package.PublisherId)
    return (Join-Path $root 'AppxManifest.xml')
}
function Assert-Identity($Id,$Package,[string]$Version){
    if($Id.Name -ne 'OpenAI.Codex' -or $Id.Publisher -ne $ExpectedPublisher -or
       [version]$Id.Version -ne [version]$Version -or
       $Id.ProcessorArchitecture -ne $Package.Architecture.ToString().ToLowerInvariant()){
        throw 'Package name, publisher, architecture, or target version does not match.'
    }
}
function Assert-Package($Package,$Data){
    if($Data.sid -ne $ExpectedSid){throw 'The updater is running as a different Windows account.'}
    if([version]$Data.targetVersion -le [version]$Package.Version){throw 'The target is not newer than the registered package. Diagnose again.'}
    if($Data.register){
        $expected=Get-StagedPath $Package $Data.targetVersion
        if(-not [IO.Path]::GetFullPath($Data.packagePath).Equals([IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected staged package path.'}
        [xml]$manifest=Get-Content -LiteralPath $expected -Raw -Encoding UTF8
        $id=$manifest.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Identity']")
        Assert-Identity $id $Package $Data.targetVersion
        $app=Get-AppEntry $Package
        $currentExe=Join-Path $Package.InstallLocation $app.Executable
        $targetExe=Join-Path (Split-Path $expected) $app.Executable
        $currentSignature=Get-AuthenticodeSignature -LiteralPath $currentExe
        $targetSignature=Get-AuthenticodeSignature -LiteralPath $targetExe
        if($currentSignature.Status -ne 'Valid' -or $targetSignature.Status -ne 'Valid' -or
           $currentSignature.SignerCertificate.Subject -ne $targetSignature.SignerCertificate.Subject){throw 'Staged application signature verification failed.'}
    }else{
        $expectedCache=Join-Path (Split-Path $InputPath) 'package.msix'
        if(-not [IO.Path]::GetFullPath($Data.packagePath).Equals([IO.Path]::GetFullPath($expectedCache),[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected downloaded package path.'}
        $signature=Get-AuthenticodeSignature -LiteralPath $Data.packagePath
        if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -ne $ExpectedPublisher){throw 'Downloaded MSIX signature or publisher is invalid.'}
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip=[IO.Compression.ZipFile]::OpenRead($Data.packagePath)
        try{
            $entry=$zip.GetEntry('AppxManifest.xml')
            if(-not $entry){throw 'MSIX manifest is missing.'}
            $reader=New-Object IO.StreamReader($entry.Open())
            try{[xml]$manifest=$reader.ReadToEnd()}finally{$reader.Dispose()}
            $id=$manifest.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Identity']")
            Assert-Identity $id $Package $Data.targetVersion
        }finally{$zip.Dispose()}
    }
}
function Write-AtomicJson([string]$Path,$Value){
    [IO.File]::WriteAllText("$Path.tmp",($Value|ConvertTo-Json -Depth 6 -Compress),(New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath "$Path.tmp" -Destination $Path -Force
}

try{
    Import-Module Appx
    $value=$null
    switch($Operation){
        'Identity' { $value=@{sid=$ExpectedSid;sessionId=$SessionId} }
        'Inspect' {
            $p=Get-CodexPackage
            if($p){
                $app=Get-AppEntry $p
                $value=@{name=$p.Name;version=$p.Version.ToString();architecture=$p.Architecture.ToString().ToLowerInvariant();publisher=$p.Publisher;family=$p.PackageFamilyName;location=$p.InstallLocation;appId=$app.Id;processes=@(Get-CodexProcesses $p | ForEach-Object {@{id=$_.Id;path=$_.Path}})}
            }
        }
        'Staged' {
            $p=Get-CodexPackage
            if(-not $p){throw 'Codex package not found.'}
            $path=Get-StagedPath $p $inputData.targetVersion
            $exists=Test-Path -LiteralPath $path -PathType Leaf
            if($exists){
                [xml]$m=Get-Content -LiteralPath $path -Raw -Encoding UTF8
                Assert-Identity $m.Package.Identity $p $inputData.targetVersion
            }
            $value=@{exists=$exists;path=$(if($exists){$path}else{''})}
        }
        'Validate' { $p=Get-CodexPackage; if(-not $p){throw 'Codex package not found.'}; Assert-Package $p $inputData; $value=@{valid=$true} }
        'Activity' { $value=@{activity=(Get-CodexActivity (Get-CodexPackage))} }
        'Quit' {
            if($inputData.sid -ne $ExpectedSid){throw 'Different Windows user.'}
            $p=Get-CodexPackage
            $value=Stop-CodexForUpdate $p $false
        }
        'ForceQuit' {
            if($inputData.confirmed -ne $true -or $inputData.sid -ne $ExpectedSid){throw 'Explicit force-quit confirmation is required.'}
            $p=Get-CodexPackage
            $value=Stop-CodexForUpdate $p $true
        }
        'Deploy' {
            $root=Split-Path (Split-Path (Split-Path $InputPath))
            $deploymentLock=[IO.File]::Open((Join-Path $root 'deployment.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
            try{
            $p=Get-CodexPackage
            if(-not $p){throw 'Codex package not found.'}
            Assert-Package $p $inputData
            if(@(Get-CodexOccupants $p).Count -gt 0){throw 'Codex is still running. No deployment was started.'}
            $progressPath=Join-Path (Split-Path $InputPath) 'deployment-progress.json'
            $job=Start-Job -ArgumentList $inputData.packagePath,([bool]$inputData.register) -ScriptBlock {
                param($Path,$RegisterStaged)
                $ErrorActionPreference='Stop'
                $ProgressPreference='Continue'
                $env:PSModulePath="$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
                Import-Module Appx
                # Windows can retain an active app service after its visible processes exit.
                if($RegisterStaged){Add-AppxPackage -Path $Path -Register -DisableDevelopmentMode -ForceTargetApplicationShutdown -ErrorAction Stop}
                else{Add-AppxPackage -Path $Path -ForceTargetApplicationShutdown -ErrorAction Stop}
            }
            try{
                do{
                    $records=@($job.ChildJobs[0].Progress)
                    $percent=$null
                    if($records.Count -gt 0 -and $records[-1].PercentComplete -ge 0){$percent=$records[-1].PercentComplete}
                    Write-AtomicJson $progressPath @{percent=$percent;time=(Get-Date).ToUniversalTime().ToString('o')}
                    if($job.State -notin @('Running','NotStarted')){break}
                    Start-Sleep -Milliseconds 700
                }while($true)
                Receive-Job -Job $job -ErrorAction Stop | Out-Null
                if($job.State -ne 'Completed'){throw 'Windows deployment job did not complete.'}
            }finally{Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}
            $current=Get-CodexPackage
            if([version]$current.Version -lt [version]$inputData.targetVersion){throw 'Windows did not register the target version.'}
            $value=@{version=$current.Version.ToString();deployed=$true}
            }finally{$deploymentLock.Dispose()}
        }
        'Launch' {
            $p=Get-CodexPackage
            if(-not $p){throw 'Codex package not found.'}
            if($inputData.sid -ne $ExpectedSid){throw 'Different Windows user.'}
            $entry=Get-AppEntry $p
            Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('shell:AppsFolder\'+$p.PackageFamilyName+'!'+$entry.Id) | Out-Null
            $value=@{requested=$true}
        }
        'Prompt' {
            $p=Get-CodexPackage
            $processes=@(Get-CodexProcesses $p)
            Add-Type -AssemblyName UIAutomationClient
            Add-Type -AssemblyName UIAutomationTypes
            $maxButtons=0
            $visible=$false
            foreach($process in $processes){
                $pc=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty,$process.Id)
                $windows=[System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,$pc)
                foreach($window in $windows){
                    if($window.Current.IsOffscreen){continue}
                    $bc=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button)
                    $buttons=$window.FindAll([System.Windows.Automation.TreeScope]::Descendants,$bc)
                    $maxButtons=[Math]::Max($maxButtons,$buttons.Count)
                    foreach($button in $buttons){
                        if(-not $button.Current.IsOffscreen -and $button.Current.Name -match '^(\u6709\u53ef\u7528\u66f4\u65b0|\u66f4\u65b0\u53ef\u7528|\u91cd\u542f\u4ee5\u66f4\u65b0|\u91cd\u65b0\u542f\u52a8\u4ee5\u66f4\u65b0|\u7acb\u5373\u66f4\u65b0|\u5b89\u88c5\u66f4\u65b0|Update available|Update ready|Restart to update|Restart and update|Install update|Update and restart)([.!\s]|$)'){$visible=$true}
                    }
                }
            }
            # Absence is only an observation of a sufficiently populated accessibility tree.
            $value=@{prompt=$(if($visible){'visible'}elseif($maxButtons -ge 10){'not_detected'}else{'unverified'})}
        }
        'Events' {
            $event=Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-AppXDeploymentServer/Operational';StartTime=(Get-Date).AddDays(-1);Id=638,419,401,404} -MaxEvents 80 -ErrorAction SilentlyContinue | Where-Object {$_.Message -match 'OpenAI\.Codex' -and $_.Message -match '800700E9|80073D02|\u4ecd\u5728\u8fd0\u884c|\u9700\u8981\u5173\u95ed|in use|still running'} | Select-Object -First 1
            $value=@{blocked=([bool]$event);time=$(if($event){$event.TimeCreated.ToUniversalTime().ToString('o')}else{$null});eventId=$(if($event){$event.Id}else{$null})}
        }
    }
    @{ok=$true;value=$value}|ConvertTo-Json -Depth 10 -Compress
}catch{
    $message=$_.Exception.Message
    if($message.Length -gt 2000){$message=$message.Substring(0,2000)}
    @{ok=$false;error=$message;hresult=$_.Exception.HResult}|ConvertTo-Json -Depth 3 -Compress
    exit 1
}
