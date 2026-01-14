#!/bin/bash

echo "🚀 Starting Deep Clean..."

# 1. Clean Flutter build artifacts
echo "🧹 Running flutter clean..."
flutter clean

# 2. Delete iOS dependencies and workspaces to force regeneration
echo "🗑️  Removing ios/Pods, ios/Runner.xcworkspace, ios/Podfile.lock..."
rm -rf ios/Pods
rm -rf ios/Runner.xcworkspace
rm -f ios/Podfile.lock
rm -rf build

# 3. Strip extended attributes (The Fix for 'resource fork' errors)
# This removes hidden metadata that macOS/iCloud attaches to files
echo "🧼 Stripping extended attributes (xattr)..."
xattr -cr .

# 4. Merge split resource forks
echo "🔗 Running dot_clean..."
dot_clean -m .

# 5. Re-install dependencies
echo "📦 Re-installing dependencies..."
flutter pub get

echo "🍎 Installing iOS Pods..."
cd ios
pod install
cd ..

echo "✅ Clean complete! Please run 'flutter run' now."
