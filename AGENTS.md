# Project

- **PROJECT_NAME**: Swara
- **PROJECT_KIND**: app (Android, Flutter)
- **DESCRIPTION**: Offline music player with metadata, lyrics, statistics and backup.
- **DEFAULT_BRANCH**: main
- **PIPELINE**: direct (work pushes straight to main; CI verifies on every push)
- **VERSIONING**: `MAJOR.MINOR.PATCH+BUILD` in `pubspec.yaml` (for example `3.11.0+61`), tag `vX.Y.Z`
- **RELEASE_TITLE**: `Swara vX.Y.Z`
- **MIN_OS**: Android 8.0 (API 26)
- **PACKAGE_MANIFEST**: `pubspec.yaml`
- **BUILD**: `flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64 --obfuscate --split-debug-info=build/symbols`
- **VERIFY**: `flutter analyze` and `flutter test` both clean
- **RELEASE_FLOW**: push to main, wait for CI green, tag `vX.Y.Z`, push the tag. The Build & Release workflow builds the split APKs and creates the GitHub Release from `CHANGELOG.md` and `CHANGELOG.id.md` via `scripts/release_body.py`, with `app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk` and `app-x86_64-release.apk` attached. Notes are bilingual, English first; `## Install / Update` matches README Installation, Option A.
- **CHANGELOG**: `CHANGELOG.md` and `CHANGELOG.id.md`, both updated for every release
- **README**: `README.md` and `README.id.md`, kept in sync
- **SECURITY_KIND**: app (release gate applies; APKs are currently signed with the debug keystore, see Open items)
- **OPEN_ITEMS**: APK signing uses the debug keystore. The release keystore is held by the project owner; switching the signing config blocks on that key.
