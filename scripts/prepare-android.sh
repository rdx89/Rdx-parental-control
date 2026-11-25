#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
if [ -f android/gradlew ] && [ -f android/gradlew.bat ] &&
   [ -f android/gradle/wrapper/gradle-wrapper.jar ] &&
   [ -f android/gradle/wrapper/gradle-wrapper.properties ]; then
    exit 0
fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
flutter create --platforms=android --no-pub --project-name safeguard_bootstrap "$scratch"
mkdir -p android/gradle/wrapper
cp "$scratch/android/gradlew" "$scratch/android/gradlew.bat" android/
cp "$scratch/android/gradle/wrapper/gradle-wrapper.jar" android/gradle/wrapper/
cp "$scratch/android/gradle/wrapper/gradle-wrapper.properties" android/gradle/wrapper/
sed -i 's@gradle-[0-9.]*-\(all\|bin\)\.zip@gradle-8.13-bin.zip@' android/gradle/wrapper/gradle-wrapper.properties
chmod +x android/gradlew
