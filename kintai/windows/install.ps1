# 勤怠記録のセットアップ（職員のPCで、その職員がログインした状態で実行）
#
# 使い方:
#   右クリック →「PowerShell で実行」、または
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Name 山田
#
#   -Name       管理画面に表示する名前（必須）
#   -FolderPath 本人用フォルダの場所（省略時は OneDrive 内の「勤怠_名前」フォルダを自動で探す）
param(
    [string]$Name,
    [string]$FolderPath,
    [string]$FolderName,
    [int]$IntervalMinutes = 15
)

$ErrorActionPreference = 'Stop'

if (-not $Name) { $Name = Read-Host '管理画面に表示する名前を入力してください（例: 山田）' }
$Name = ($Name -replace '[,\r\n"\\/:*?<>|]', ' ').Trim()
if (-not $Name) { throw '名前が空です。' }
if (-not $FolderName) { $FolderName = "勤怠_$Name" }

# --- 共有フォルダを探す ---
if (-not $FolderPath) {
    $roots = @($env:OneDriveCommercial, $env:OneDriveConsumer, $env:OneDrive) |
        Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    foreach ($root in $roots) {
        $found = Get-ChildItem -Path $root -Directory -Depth 1 -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $FolderName } | Select-Object -First 1
        if ($found) { $FolderPath = $found.FullName; break }
    }
}
if (-not $FolderPath -or -not (Test-Path $FolderPath)) {
    Write-Host "OneDrive の中に「$FolderName」フォルダが見つかりませんでした。" -ForegroundColor Yellow
    Write-Host 'README の「1. 職員ごとのフォルダを用意する」を済ませてから、もう一度実行してください。'
    Write-Host 'フォルダの場所が分かっている場合は -FolderPath で指定できます。'
    Read-Host 'Enter キーで閉じます'
    exit 1
}

# --- プログラムと設定を PC 内にコピー ---
$appDir = Join-Path $env:LOCALAPPDATA 'Kintai'
New-Item -ItemType Directory -Force -Path $appDir | Out-Null
$scriptPath = Join-Path $appDir 'kintai-log.ps1'
Copy-Item -Force (Join-Path $PSScriptRoot 'kintai-log.ps1') $scriptPath
Unblock-File $scriptPath -ErrorAction SilentlyContinue

$config = @{ Name = $Name; Folder = $FolderPath } | ConvertTo-Json
[System.IO.File]::WriteAllText((Join-Path $appDir 'config.json'), $config, (New-Object System.Text.UTF8Encoding $true))

# --- タスクスケジューラに登録 ---
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$taskPath = '\Kintai\'

function New-KintaiAction([string]$type) {
    # conhost --headless で、黒い画面を一瞬も出さずに実行する
    New-ScheduledTaskAction -Execute 'conhost.exe' -Argument (
        "--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass " +
        "-File `"$scriptPath`" -Type $type")
}

$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances Queue

$stateClass = Get-CimClass -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskSessionStateChangeTrigger'
function New-SessionTrigger([int]$state) {
    # 7 = ロック, 8 = ロック解除
    New-CimInstance -CimClass $stateClass -ClientOnly -Property @{ StateChange = $state; UserId = $user; Enabled = $true }
}

$heartbeat = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)

$tasks = @(
    @{ Name = 'Kintai-Logon';  Event = 'logon';  Trigger = (New-ScheduledTaskTrigger -AtLogOn -User $user) },
    @{ Name = 'Kintai-Unlock'; Event = 'unlock'; Trigger = (New-SessionTrigger 8) },
    @{ Name = 'Kintai-Lock';   Event = 'lock';   Trigger = (New-SessionTrigger 7) },
    @{ Name = 'Kintai-Active'; Event = 'active'; Trigger = $heartbeat }
)

foreach ($t in $tasks) {
    Register-ScheduledTask -TaskPath $taskPath -TaskName $t.Name -Force `
        -Action (New-KintaiAction $t.Event) -Trigger $t.Trigger `
        -Principal $principal -Settings $settings `
        -Description '勤怠記録（ログイン時刻を OneDrive に記録）' | Out-Null
}

# --- 動作確認 ---
$csv = Join-Path $FolderPath "$Name.csv"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Type install
$before = if (Test-Path $csv) { (Get-Content $csv).Count } else { 0 }
Start-ScheduledTask -TaskPath $taskPath -TaskName 'Kintai-Active'
Start-Sleep -Seconds 5
$after = if (Test-Path $csv) { (Get-Content $csv).Count } else { 0 }

Write-Host ''
if ($before -gt 0 -and $after -gt $before) {
    Write-Host "セットアップ完了：$Name さんの記録は $csv に保存されます。" -ForegroundColor Green
} elseif ($before -gt 0) {
    Write-Host '記録ファイルは作れましたが、自動実行の確認ができませんでした。' -ForegroundColor Yellow
    Write-Host 'Windows が古い場合に起きることがあります。README の「困ったとき」を見てください。'
} else {
    Write-Host '記録ファイルを作れませんでした。OneDrive にサインインしているか確認してください。' -ForegroundColor Red
}
Write-Host ''
Read-Host 'Enter キーで閉じます'
