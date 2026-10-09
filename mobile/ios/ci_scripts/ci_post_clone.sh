#!/bin/sh
# Xcode Cloud: install Flutter and generate the files the Xcode build expects
# (Flutter/Generated.xcconfig and Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage).
set -e

FLUTTER_VERSION="3.44.6"

git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

flutter config --enable-swift-package-manager
flutter precache --ios

cd "$CI_PRIMARY_REPOSITORY_PATH/mobile"
flutter pub get
flutter build ios --config-only --release --no-codesign
