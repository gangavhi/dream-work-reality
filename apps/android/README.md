# Android Scaffold

This directory contains a small native Android scaffold that mirrors the iOS demo surface for the Rust `core-api` backend.

## Prerequisites

- JDK 17+
- Android SDK command-line tools
- Android platform SDK 36 and build-tools 36.0.0
- Gradle 9.4.1+

## Build

```bash
cd apps/android
ANDROID_HOME=/opt/android-sdk ./gradlew :app:assembleDebug
```

If you do not have the Gradle wrapper yet, generate it with a local Gradle install:

```bash
cd apps/android
gradle wrapper --gradle-version 9.4.1
```

## Run on emulator

Start `core-api` on the host first:

```bash
cd core
cargo run -p core_api
```

Then boot an Android emulator and install the debug APK:

```bash
cd apps/android
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.dreamwork.app/.MainActivity
```

The app uses `http://10.0.2.2:18081` so an emulator can reach the host `core-api`
service through the same local port expected by the browser extension demo.
