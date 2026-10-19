# 勤怠記録：ログイン・ロック解除などの時刻を OneDrive の共有フォルダに書き込みます。
# タスクスケジューラから自動で呼ばれます（install.ps1 が登録）。
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('logon', 'unlock', 'lock', 'active', 'install')]
    [string]$Type
)

$ErrorActionPreference = 'Stop'
$appDir = Join-Path $env:LOCALAPPDATA 'Kintai'
$configPath = Join-Path $appDir 'config.json'
$pendingPath = Join-Path $appDir 'pending.csv'
$utf8Bom = New-Object System.Text.UTF8Encoding $true

$config = Get-Content -Raw -Encoding UTF8 $configPath | ConvertFrom-Json

# 定期記録（active）は、画面がロック中なら何もしない
if ($Type -eq 'active' -and (Get-Process -Name LogonUI -ErrorAction SilentlyContinue)) {
    exit 0
}

$name = ($config.Name -replace '[,\r\n"]', ' ').Trim()
$pc = $env:COMPUTERNAME
$now = (Get-Date).ToString('yyyy-MM-dd\THH:mm:sszzz', [System.Globalization.CultureInfo]::InvariantCulture)
$line = "$now,$name,$pc,$Type`r`n"
$header = "日時,名前,PC,種類`r`n"

function Write-Line([string]$path, [string]$text) {
    if (-not (Test-Path $path)) {
        [System.IO.File]::AppendAllText($path, $header, $utf8Bom)
    }
    # OneDrive の同期中にファイルが一時的に使えないことがあるので数回やり直す
    for ($i = 0; $i -lt 5; $i++) {
        try {
            [System.IO.File]::AppendAllText($path, $text, $utf8Bom)
            return
        } catch {
            Start-Sleep -Milliseconds 800
        }
    }
    throw "書き込みに失敗しました: $path"
}

$target = Join-Path $config.Folder "$name.csv"

try {
    if (-not (Test-Path $config.Folder)) { throw 'フォルダが見つかりません' }

    # 前回書けなかった分があれば先に書く
    if (Test-Path $pendingPath) {
        $pending = [System.IO.File]::ReadAllText($pendingPath, $utf8Bom)
        if ($pending.Length -gt 0) { Write-Line $target $pending }
        Remove-Item $pendingPath -Force
    }
    Write-Line $target $line
} catch {
    # OneDrive に書けないときはPC内に一時保存し、次回まとめて書く
    [System.IO.File]::AppendAllText($pendingPath, $line, $utf8Bom)
}
