$ErrorActionPreference='Stop'
$paths=@('src-tauri\scripts\windows.ps1')
foreach($path in $paths){
    $tokens=$null;$parseErrors=$null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path $PSScriptRoot) $path),[ref]$tokens,[ref]$parseErrors)|Out-Null
    if($parseErrors.Count -gt 0){throw ($parseErrors|Out-String)}
    Write-Output "Syntax OK: $path"
}
