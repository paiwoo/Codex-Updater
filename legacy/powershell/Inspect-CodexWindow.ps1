param([Parameter(Mandatory=$true)][int]$AppProcessId)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$app = Get-Process -Id $AppProcessId
if ($app.MainWindowHandle -eq [IntPtr]::Zero) { throw 'Codex has no visible main window.' }
$processCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $AppProcessId)
$windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
    [System.Windows.Automation.TreeScope]::Children, $processCondition)
$condition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
$buttonCount=0
$windowCount=0
$updates = @()
foreach($window in $windows){
    if($window.Current.IsOffscreen){continue}
    # Codex owns multiple windows; MainWindowHandle may point to an empty browser/sidebar.
    $null=$window.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
    Start-Sleep -Milliseconds 500
    $buttons=$window.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition)
    $buttonCount=[Math]::Max($buttonCount,$buttons.Count)
    $windowCount++
    foreach ($button in $buttons) {
        $name = $button.Current.Name
        if (-not $button.Current.IsOffscreen -and
            $name -match '^(有可用更新|更新可用|重启以更新|重新启动以更新|立即更新|安装更新|Update available|Update ready|Restart to update|Restart and update|Install update|Update and restart)([.!。！…\s]|$)') {
            $updates += $name
        }
    }
}
[ordered]@{
    accessible = $buttonCount -ge 10
    windowCount = $windowCount
    buttonCount = $buttonCount
    updatePromptVisible = $updates.Count -gt 0
    updateButtons = $updates
} | ConvertTo-Json -Compress
