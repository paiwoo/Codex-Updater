param([ValidateSet('check','test','build','fmt')][string]$Action='test')
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot
$taskLocalCargo=Join-Path $taskRoot '.tooling\cargo\bin\cargo.exe'
if(Test-Path -LiteralPath $taskLocalCargo){
    $env:CARGO_HOME=Join-Path $taskRoot '.tooling\cargo'
    $env:RUSTUP_HOME=Join-Path $taskRoot '.tooling\rustup'
    $taskCargo=$taskLocalCargo
}else{
    $taskCargo=(Get-Command cargo -ErrorAction Stop).Source
}
$taskArgs=@($Action,'--manifest-path',(Join-Path $taskRoot 'src-tauri\Cargo.toml'))
if($Action -ne 'fmt' -and -not (Test-Path -LiteralPath (Join-Path $taskRoot 'src-tauri\resources\THIRD_PARTY_LICENSES.txt'))){
    & node (Join-Path $PSScriptRoot 'collect-notices.mjs')
    if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
}
if($Action -ne 'fmt'){$taskArgs+='--locked'}
& $taskCargo @taskArgs
exit $LASTEXITCODE
