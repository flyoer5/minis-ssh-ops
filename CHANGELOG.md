# Changelog

## Unreleased

### Security and build hardening

- Restore command risk classification, confirmation gates, and blocking for destructive host operations.
- Remove any exposed Android signing key from the tree; release signing must rely on Actions secrets and never fall back to a debug key.
- Pin CI toolchains and actions, add dependency updates, and keep the Flutter lockfile committed for reproducible builds.
- Treat any previously committed Android keystore and passwords as compromised until they are replaced.

### UX polish

- Agent: clearer empty copy by host selection, animated jump-to-bottom, improved drag behavior, and clearer snackbars.
- Errors: friendlier DNS, dial, TLS, and 502 model gateway messages without raw resolver dumps.
- Hosts: clearer search hint, better no-match state, and cleaner empty-state copy.
- Files: empty directories now show the path and a refresh action.
- Settings: shorter confirmation-policy copy.
- Terminal: snackbar duration set to 2 seconds.
- Defaults: probe concurrency reset aligns with 4.

### Startup and performance

- Paint HomeShell as soon as the backend is healthy; defer host and LLM loading until after first frame.
- Avoid redundant health polling.
- Reduce network and probe timeouts where appropriate.
- Shorten probe CPU sampling delay for faster host refreshes.
- Skip SSH keepalive RTT when the connection was used recently.
- Use more efficient SQLite settings for local storage.
- Reduce backend log flush frequency.
- Tighten Agent stream UI throttling and align default probe concurrency.

### Android DNS

- Fix Android model DNS failures by preferring a Go resolver path instead of localhost DNS fallback.

### IME behavior

- Keep text fields focused while the keyboard opens.
- Avoid unnecessary tree remounts when adjusting for the IME.
- Remove black bands and layout jank around the keyboard.

## Previous releases

The full historical notes were simplified during repository cleanup. The versioned release record remains in the git history.
