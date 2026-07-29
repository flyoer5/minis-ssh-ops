# Security

## Trust Boundaries

- The embedded Go service listens only on `127.0.0.1`.
- Protected REST endpoints require `X-Local-Token`.
- PTY WebSocket accepts the local token in the query string for client compatibility.
- Remote backend URLs must use HTTPS. Cleartext HTTP is restricted to loopback addresses.
- SSH host keys use trust on first use and are persisted locally.

## Credentials

SSH passwords, private keys, private-key passphrases and model API keys are encrypted before being stored in SQLite. API responses never return plaintext SSH credentials.

Host updates use explicit `clearPassword`, `clearPrivateKey` and `clearPassphrase` fields. The backend rejects updates that would leave a host without any usable authentication credential.

Sensitive local files are excluded by `.gitignore`, including:

- `local.token`
- `master.key`
- SQLite databases
- Android signing properties and keystores
- generated Go binaries

## Command Execution

Commands are parsed with a shell parser and classified as `read`, `write`, `destructive` or `blocked`.

- `write` and `destructive` operations pass through confirmation controls.
- `blocked` commands are always rejected.
- The backend enforces these controls; model output and Flutter requests are not trusted to bypass them.
- Executed operations are recorded in the local audit log.

## Android Signing

Never commit signing material. Local setup may use `app/android/key.properties`, based on `app/android/key.properties.example`.

CI release signing requires all four repository Secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

The `Android Release` workflow requires all four secrets and fails before building if any are missing. The regular CI workflow may still skip its optional release APK when no signing secrets are configured.

Any keystore previously committed to public history must be treated as compromised. This repository does not rewrite public history as part of normal maintenance.

## Reporting

Do not open a public issue containing credentials, private keys, access tokens, host addresses or exploit details. Revoke exposed credentials immediately before reporting the underlying problem through a private channel available to the repository owner.

## Known Hardening Work

- Move Flutter-held local tokens out of ordinary preferences.
- Protect the database master key with Android Keystore.
- Add atomic persistence and concurrency coverage for known-hosts updates.
- Add explicit request and file-size limits to file APIs.
