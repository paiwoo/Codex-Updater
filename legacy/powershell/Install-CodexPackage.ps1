param(
    [Parameter(Mandatory=$true)][string]$PackagePath,
    [Parameter(Mandatory=$true)][string]$ExpectedVersion,
    [Parameter(Mandatory=$true)][string]$ExpectedSid,
    [switch]$Register
)
$ErrorActionPreference='Stop'
$env:PSModulePath="$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
$result=[ordered]@{success=$false;version=$ExpectedVersion;message='';time=(Get-Date).ToString('o')}
$job=$null
try {
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid) {
        throw 'Elevation used a different Windows account. Refusing to install for the wrong user.'
    }
    Import-Module Appx
    $installed=Get-AppxPackage -Name OpenAI.Codex
    if(-not $installed){throw 'Official Codex is not registered for this user.'}
    if($Register){
        $expectedRoot=Join-Path (Split-Path $installed.InstallLocation) ('OpenAI.Codex_'+$ExpectedVersion+'_'+$installed.Architecture.ToString().ToLowerInvariant()+'__'+$installed.PublisherId)
        if([IO.Path]::GetFullPath($PackagePath) -ne (Join-Path $expectedRoot 'AppxManifest.xml')){throw 'Refusing to register a package outside the expected Windows staged directory.'}
        $sig=Get-AuthenticodeSignature -LiteralPath (Join-Path $expectedRoot 'app\ChatGPT.exe')
        $currentSig=Get-AuthenticodeSignature -LiteralPath (Join-Path $installed.InstallLocation 'app\ChatGPT.exe')
        if($sig.Status -ne 'Valid' -or $currentSig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -ne $currentSig.SignerCertificate.Subject){throw 'Staged executable signature validation failed.'}
        [xml]$manifest=Get-Content -LiteralPath $PackagePath -Raw -Encoding UTF8
    }else{
    $sig=Get-AuthenticodeSignature -LiteralPath $PackagePath
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -ne $installed.Publisher) { throw 'Package signature/publisher check failed in the installer.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        $reader=New-Object IO.StreamReader($zip.GetEntry('AppxManifest.xml').Open())
        try { [xml]$manifest=$reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $zip.Dispose() }
    }
    $id=$manifest.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Identity']")
    if ($id.Name -ne 'OpenAI.Codex' -or $id.Publisher -ne $installed.Publisher -or
        [version]$id.Version -ne [version]$ExpectedVersion -or
        $id.ProcessorArchitecture -ne $installed.Architecture.ToString().ToLowerInvariant()) { throw 'MSIX identity check failed in the installer.' }
    if ([version]$installed.Version -lt [version]$ExpectedVersion) {
        $job=Start-Job -ArgumentList $PackagePath,([bool]$Register) -ScriptBlock {
            param($Path,$RegisterStaged)
            $ErrorActionPreference='Stop'
            $ProgressPreference='Continue'
            $env:PSModulePath="$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
            Import-Module Appx
            if($RegisterStaged){
                Add-AppxPackage -Path $Path -Register -DisableDevelopmentMode -ForceApplicationShutdown -ErrorAction Stop
            }else{
                Add-AppxPackage -Path $Path -ForceApplicationShutdown -ErrorAction Stop
            }
        }
        do {
            $records=@($job.ChildJobs[0].Progress)
            $progress=[ordered]@{time=(Get-Date).ToString('o');percent=-1;message='Windows 部署任务运行中，等待系统报告进度';jobState=$job.State.ToString()}
            if($records.Count -gt 0){
                $last=$records[-1]
                $progress.percent=$last.PercentComplete
                $progress.message=$last.StatusDescription
            }
            $progressPath=Join-Path $PSScriptRoot 'installation-progress.json'
            [IO.File]::WriteAllText("$progressPath.tmp",($progress|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
            Move-Item -LiteralPath "$progressPath.tmp" -Destination $progressPath -Force
            if($job.State -notin @('Running','NotStarted')){break}
            Start-Sleep -Seconds 1
        }while($true)
        Receive-Job -Job $job -ErrorAction Stop | Out-Null
        if($job.State -ne 'Completed'){throw 'Windows deployment job did not complete.'}
    }
    $installed=Get-AppxPackage -Name OpenAI.Codex
    if ([version]$installed.Version -lt [version]$ExpectedVersion) { throw 'The installer did not register the target version.' }
    $result.success=$true
    $result.version=$installed.Version.ToString()
    $result.message='Windows registered the signed package successfully.'
} catch {
    $result.message=$_.Exception.Message
    $result.hresult=$_.Exception.HResult
    $result.needsElevation=$_.Exception.Message -match '80073D28|80070005|elevat|提升|管理员'
} finally {
    if($job){Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}
    $result | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'installation.json') -Encoding UTF8
}
if (-not $result.success) { exit 1 }
