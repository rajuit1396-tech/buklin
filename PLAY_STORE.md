# Buklin Android release

## Latest direct-install release

Version 1.0.18 (build 19) adds styled username cards for customers and operators.
The signed universal APK is `output/buklin-1.0.18.apk`, also published through
`backend/public/downloads/buklin.apk`. It connects to https://www.buklin.online
and includes ARM 32-bit, ARM 64-bit and x86_64 for Android 7.0 and later.
Build it with:

```powershell
flutter build apk --release --target-platform android-arm,android-arm64,android-x64 --dart-define=BACKEND_URL=https://www.buklin.online
```

The bundle and release files described below refer to the earlier 1.0.17 release.

## Phone compatibility

Minimum Android version: Android 7.0 (API 24), the minimum supported by the
installed Flutter SDK. Android 6 and earlier cannot run this build.
The universal APK includes armeabi-v7a (32-bit ARM), arm64-v8a (64-bit ARM),
and x86_64 libraries. Do not add `--split-per-abi` when creating the APK to
share with all supported phones. Play distributes the matching architecture
automatically from the app bundle.

Location hardware is optional for installation; operator arrival/start actions
still require a valid location. Background push requires OneSignal configuration.
Compatibility with every manufacturer/device is not guaranteed: verify on real
phones, including Android 7, recent Android, and both ARM architectures.

Reference: https://docs.flutter.dev/reference/supported-platforms

Google Play new listings require a signed Android App Bundle (.aab).
APKs through version 1.0.15 in output used development signing.
Version 1.0.16 introduced the new upload key and package ID.

Prepared release files:
- output/buklin-1.0.17.aab: upload to Play Console.
- output/buklin-1.0.17.apk: install directly for phone testing.

The upload key is android/upload-keystore.jks; its passwords are stored in
android/key.properties. Both are excluded from version control. Back up both
files privately so future updates can use the same key.

This build uses https://buklin-1.onrender.com and does not configure a OneSignal
app ID. Background push delivery requires that configuration and a new build.

The permanent Play package ID is `com.torikdammam.buklin`, configured in
android/app/build.gradle.kts. For an existing listing, use its registered upload key.

Create android/key.properties locally (already excluded from version control):

```properties
storeFile=upload-keystore.jks
storePassword=YOUR_LOCAL_PASSWORD
keyAlias=upload
keyPassword=YOUR_LOCAL_PASSWORD
```

The storeFile path is relative to android/, or may be an absolute path using
forward slashes. Keep the keystore and passwords backed up privately.
Do not commit or share them. Release builds stop when signing is missing.

Build using the deployed API, with a version code higher than previous uploads:

```powershell
flutter build appbundle --release --build-name=1.0.17 --build-number=18 --dart-define=BACKEND_URL=https://buklin-1.onrender.com
flutter build apk --release --target-platform android-arm,android-arm64,android-x64 --build-name=1.0.17 --build-number=18 --dart-define=BACKEND_URL=https://buklin-1.onrender.com
```

Bundle: build/app/outputs/bundle/release/app-release.aab

Phone install: build/app/outputs/flutter-apk/app-release.apk

If push notifications are configured, also supply the public
--dart-define=ONESIGNAL_APP_ID value. Never embed the OneSignal REST API key.

Upload the bundle to a Play Console internal testing release first. Complete
the store listing, privacy policy, Data safety and required declarations, then
test the installed app against the live backend before requesting production.
