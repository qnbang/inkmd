#!/bin/bash
# 소스 → 배포용 .app 묶기 (release 빌드가 이미 되어 있어야 함)
# 사용: bash 앱만들기.sh
set -e
cd "$(dirname "$0")"

NAME="inkmd"
APP="$HOME/Applications/$NAME.app"
BIN=".build/release/MDEditor"

[ -f "$BIN" ] || { echo "먼저 swift build -c release 하세요"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
[ -f "아이콘/inkmd.icns" ] && cp "아이콘/inkmd.icns" "$APP/Contents/Resources/inkmd.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>$NAME</string>
	<key>CFBundleIdentifier</key>
	<string>com.qnbang.inkmd</string>
	<key>CFBundleName</key>
	<string>$NAME</string>
	<key>CFBundleDisplayName</key>
	<string>$NAME</string>
	<key>CFBundleIconFile</key>
	<string>inkmd</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

codesign --force -s - "$APP"
echo "완성: $APP"
