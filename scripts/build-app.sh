#!/bin/bash
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$TASK_ROOT/output/续桌.app"
ICONSET_PATH="$TASK_ROOT/.build/AppIcon.iconset"
cd "$TASK_ROOT"

swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/XuZhuo"
swift scripts/create-icon.swift Resources/AppIcon.png
mkdir -p "$ICONSET_PATH"
for px in 16 32 128 256 512; do
    /usr/bin/sips -z "$px" "$px" Resources/AppIcon.png --out "$ICONSET_PATH/icon_${px}x${px}.png" >/dev/null
    doubled=$((px * 2))
    /usr/bin/sips -z "$doubled" "$doubled" Resources/AppIcon.png --out "$ICONSET_PATH/icon_${px}x${px}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET_PATH" -o Resources/AppIcon.icns

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/XuZhuo"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/AppIcon.icns"
/usr/bin/plutil -lint "$APP_PATH/Contents/Info.plist"
# Keep the identifier requirement stable between local development builds.
/usr/bin/codesign --force --sign - --identifier com.xuzhuo.app \
    --requirements '=designated => identifier "com.xuzhuo.app"' "$APP_PATH"
/usr/bin/codesign --verify --strict --verbose=2 "$APP_PATH"
/usr/bin/ditto -c -k --norsrc --keepParent "$APP_PATH" "$TASK_ROOT/output/续桌-macOS.zip"
/usr/bin/zip -qr -FS "$TASK_ROOT/output/续桌-源码.zip" \
    Package.swift scripts Resources Sources Tests docs README.md README.zh-CN.md LICENSE .gitignore -x '*/.DS_Store'
printf '已生成：%s\n压缩包：%s\n源码：%s\n' "$APP_PATH" "$TASK_ROOT/output/续桌-macOS.zip" "$TASK_ROOT/output/续桌-源码.zip"
