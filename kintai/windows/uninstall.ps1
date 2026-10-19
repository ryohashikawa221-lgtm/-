# 勤怠記録の自動実行を止めて、PC内のプログラムを削除します（記録済みの CSV は消えません）
$ErrorActionPreference = 'Continue'
Get-ScheduledTask -TaskPath '\Kintai\' -ErrorAction SilentlyContinue |
    Unregister-ScheduledTask -Confirm:$false
Remove-Item -Recurse -Force (Join-Path $env:LOCALAPPDATA 'Kintai') -ErrorAction SilentlyContinue
Write-Host '勤怠記録を削除しました。'
Read-Host 'Enter キーで閉じます'
