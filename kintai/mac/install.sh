#!/bin/bash
# 勤怠記録のセットアップ（Mac 用）
# 使い方: bash install.sh <名前> [共有フォルダのパス]
#   フォルダを省略すると、OneDrive 内の「勤怠記録」を自動で探します。
#   ※ swiftc が必要です。無い場合は先に「xcode-select --install」を実行してください。
set -euo pipefail

NAME="${1:-}"
FOLDER="${2:-}"
INTERVAL="${INTERVAL:-15}"
if [ -z "$NAME" ]; then read -r -p "管理画面に表示する名前: " NAME; fi

if [ -z "$FOLDER" ]; then
  FOLDER="$(find "$HOME/Library/CloudStorage" -maxdepth 3 -type d -name '勤怠記録' 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$FOLDER" ] || [ ! -d "$FOLDER" ]; then
  echo "OneDrive の中に「勤怠記録」フォルダが見つかりません。フォルダのパスを 2 番目に指定してください。"
  exit 1
fi

APP_DIR="$HOME/Library/Application Support/Kintai"
PLIST="$HOME/Library/LaunchAgents/com.kintai.logger.plist"
mkdir -p "$APP_DIR" "$HOME/Library/LaunchAgents"

echo "プログラムを作成しています…"
swiftc -O "$(dirname "$0")/KintaiLogger.swift" -o "$APP_DIR/kintai-logger"

xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<<"$1"; }

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.kintai.logger</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(xml_escape "$APP_DIR/kintai-logger")</string>
    <string>$(xml_escape "$NAME")</string>
    <string>$(xml_escape "$FOLDER")</string>
    <string>$INTERVAL</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

sleep 3
if [ -f "$FOLDER/$NAME.csv" ]; then
  echo "セットアップ完了：$NAME さんの記録は $FOLDER/$NAME.csv に保存されます。"
else
  echo "記録ファイルがまだ作られていません。OneDrive フォルダへのアクセス許可を求める画面が出ていたら「許可」してください。"
fi
