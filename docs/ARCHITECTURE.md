# Architecture

## Overview

Minis SSH Ops is split into a Flutter app and a local Go backend that runs on the Android device.

```text
Android application
├─ Flutter UI
│  ├─ hosts and credentials
│  ├─ terminal and files
│  ├─ AI Agent sessions
│  ├─ audit records
│  └─ settings
└─ Go backend process
   ├─ loopback HTTP API
   ├─ SSH / PTY / SFTP
   ├─ command risk analysis
   ├─ LLM orchestration
   └─ encrypted SQLite storage
```

The Android host starts the bundled Go executable as a local process. Flutter talks to it over an authenticated HTTP service bound to `127.0.0.1`.

## Flutter application

The Flutter layer owns presentation, navigation, and local UI preferences.

- `app/lib/api`: API transport and backend URL validation
- `app/lib/backend`: lifecycle integration for the embedded backend
- `app/lib/pages`: hosts, Agent, terminal, files, records, and settings
- `app/lib/state`: application state and Agent session coordination
- `app/assets/terminal`: terminal web-view assets

SSH credentials and model secrets are not returned to Flutter after they are saved. Host records only expose safe flags such as `hasPassword` and `hasPrivateKey`.

## Go backend

The Go service owns sensitive data and remote operations.

- `backend/internal/api`: HTTP handlers, authentication, and WebSocket PTY
- `backend/internal/sshx`: SSH connections, pooling, host keys, PTY, and SFTP
- `backend/internal/risk`: shell parsing and command risk classification
- `backend/internal/agent`: model client, planning, execution, and memory
- `backend/internal/store`: SQLite persistence and secret encryption
- `backend/internal/crypto`: AES-256-GCM envelope encryption

The service binds only to loopback and requires a random local token for protected endpoints.

## Data flow

### SSH operations

1. Flutter sends a protected request with `X-Local-Token`.
2. The backend loads and decrypts the selected host credentials.
3. The SSH pool isolates sessions by endpoint, username, and credential fingerprints.
4. The backend executes the operation and records the audit data.
5. Only operation output and public host metadata return to Flutter.

### Agent operations

1. Flutter submits the user goal and selected host context.
2. The backend calls the configured OpenAI-compatible model.
3. Proposed commands are parsed and classified locally.
4. Confirmation is enforced by the backend, independent of model output.
5. Approved steps run through the same SSH and audit layers as manual commands.

## Storage

SQLite stores hosts, encrypted credentials, settings, Agent sessions, messages, memory, and audit records. Secret values are encrypted with AES-256-GCM using a locally generated master key.

The current implementation stores the master key in the application data directory. Moving that key into Android Keystore is a future hardening task.

## Networking

- Embedded backend: HTTP on loopback only
- Remote backend configuration: HTTPS required
- Loopback remote configuration: HTTP allowed for `localhost`, `127.0.0.1`, and IPv6 loopback
- Model provider: direct connection from the backend to the user-configured endpoint
- SSH: direct connection from the device to configured hosts

## Build

`scripts/build-go-android.sh` cross-compiles the Go server for `android/arm64`, copies it into Android assets, and duplicates it as a `.so`-named native library for packaging. The generated binaries are excluded from Git.

GitHub Actions runs Go tests, a Linux backend smoke test, Flutter analysis and tests, and an arm64 APK build. Release signing runs only when all required signing secrets are configured.
