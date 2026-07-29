# Releasing

正式 Android releases are built by the GitHub Actions `Android Release` workflow. The workflow uses the repository's existing Android signing material; it does not generate or rotate a signing key.

## Configure signing secrets

In **Settings -> Secrets and variables -> Actions**, configure these four repository secrets:

- `ANDROID_KEYSTORE_BASE64`: Base64 content of the existing `release.jks`
- `ANDROID_STORE_PASSWORD`: keystore password
- `ANDROID_KEY_PASSWORD`: signing key password
- `ANDROID_KEY_ALIAS`: signing key alias

Keep signing material in GitHub Secrets. Do not commit `key.properties`, `.jks`, or `.keystore` files. A release fails before building if any secret is missing.

## Publish a release

1. Update `version` in `app/pubspec.yaml`, for example `1.5.39+123`.
2. Merge the version change into `main`.
3. Create and push a tag from that `main` commit:

   ```bash
   git tag v1.5.39
   git push origin v1.5.39
   ```

4. Monitor the `Android Release` workflow. On success, the GitHub Release contains the versioned APK, a `latest` APK, and `SHA256SUMS.txt`.

Tags must use the exact `vMAJOR.MINOR.PATCH` format. The version without `v` must match the part of `app/pubspec.yaml` before `+`. The workflow can also be run manually with an existing `v*` tag.

## Key rotation

This workflow does not rotate signing keys automatically. If the key is exposed, follow the Android app release policy and update all four secrets. Never commit either the old or new keystore to the repository or its public history.
