#!/bin/bash
set -euo pipefail

app="$1"
identity="$2"
framework="$app/Contents/Frameworks/Sparkle.framework"

# Sign nested code from the inside out. In particular, Downloader.xpc needs
# its own entitlement preserved; --deep would replace it with the app's.
codesign --force --sign "$identity" --options runtime \
  "$framework/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign "$identity" --options runtime --preserve-metadata=entitlements \
  "$framework/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign "$identity" --options runtime \
  "$framework/Versions/B/Autoupdate"
codesign --force --sign "$identity" --options runtime \
  "$framework/Versions/B/Updater.app"
codesign --force --sign "$identity" --options runtime "$framework"
codesign --force --sign "$identity" --identifier com.nh.uswitch "$app"
codesign --verify --deep --strict "$app"
