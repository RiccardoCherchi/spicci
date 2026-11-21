#!/bin/sh
# Builds an unsigned .ipa for SideStore or AltStore, which re-sign it with your Apple ID.
set -e
cd "$(dirname "$0")/.."
flutter build ios --release --no-codesign
rm -rf build/sideload && mkdir -p build/sideload/Payload dist
cp -R build/ios/iphoneos/Runner.app build/sideload/Payload/
(cd build/sideload && zip -qr ../../dist/Spicci.ipa Payload)
# The release build leaves native assets that break the next simulator run.
flutter clean > /dev/null
echo "Built $(pwd)/dist/Spicci.ipa"
