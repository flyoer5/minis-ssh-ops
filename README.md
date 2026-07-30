# Minis SSH Ops

Minis SSH Ops is an Android SSH client for personal ops work. It ships a Flutter UI for hosts, terminal, files, audit records, settings, and AI Agent sessions, plus a Go backend that runs locally on the device and exposes SSH features over loopback HTTP.

## What it includes

- SSH authentication with passwords and private keys
- Interactive terminal and SFTP file management
- Host probing, command execution, and local audit records
- OpenAI-compatible model integration and multi-step Agent execution
- Command risk classification, confirmation gates, and destructive-command blocking
- SSH host-key TOFU verification
- Encrypted local storage for SSH credentials and model API keys

## Repository layout

```text
app/        Flutter app and Android host shell
backend/    Local Go service for SSH, Agent, storage and HTTP API
docs/       Architecture and documentation notes
scripts/    Development, build and smoke-test helpers
.github/    CI and dependency workflow configuration
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the system overview and [scripts/README.md](scripts/README.md) for script notes.

## Requirements

- Go 1.25+
- Flutter 3.44+
- Android SDK and NDK for APK builds

## Common tasks

Run the backend locally:

```bash
./scripts/run-backend.sh
```

Run backend tests:

```bash
cd backend
go test ./...
```

Run Flutter checks:

```bash
cd app
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

Build the Android arm64 backend and debug APK:

```bash
./scripts/build-go-android.sh
cd app
flutter build apk --debug --target-platform android-arm64
# Release（需要签名配置；请妥善保存 build/debug-info）
flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/debug-info
```

## Security notes

- The Go backend listens on `127.0.0.1` only.
- Protected API calls use `X-Local-Token`.
- Remote backend URLs must use HTTPS unless they are loopback addresses.
- SSH passwords, private keys, passphrases, and model API keys are encrypted before being written to SQLite.
- Android keystore material, signing passwords, the database, and generated Go binaries should not be committed.

See [SECURITY.md](SECURITY.md) for the full boundary model.

## CI

GitHub Actions builds and tests the project on push, pull request, and manual dispatch:

- Go unit tests and a Linux backend smoke run
- Android arm64 Go cross-compilation
- Flutter analyze and Flutter tests
- Debug APK build and SHA-256 packaging
- Release APK build only when all signing secrets are present

## Changelog

Version history lives in [CHANGELOG.md](CHANGELOG.md).
