#!/bin/bash
# 勤怠記録（Mac 用）を停止・削除します（記録済みの CSV は消えません）
PLIST="$HOME/Library/LaunchAgents/com.kintai.logger.plist"
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$HOME/Library/Application Support/Kintai"
echo "勤怠記録を削除しました。"
