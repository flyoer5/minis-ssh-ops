# 发布说明

正式 Android 版本由 GitHub Actions 的 `Android Release` 工作流构建。工作流使用仓库现有的 Android 签名材料，不会生成或轮换签名密钥。

## 配置签名 Secrets

在仓库的 **Settings -> Secrets and variables -> Actions** 中配置以下四个 Repository secrets：

- `ANDROID_KEYSTORE_BASE64`：现有 `release.jks` 的 Base64 内容
- `ANDROID_STORE_PASSWORD`：keystore 密码
- `ANDROID_KEY_PASSWORD`：签名密钥密码
- `ANDROID_KEY_ALIAS`：签名密钥别名

签名材料只能保存在 GitHub Secrets 中。不要提交 `key.properties`、`.jks` 或 `.keystore` 文件。缺少任一 Secret 时，正式发布会在构建前失败。

## 发布步骤

1. 更新 `app/pubspec.yaml` 中的 `version`，例如 `1.5.39+123`。
2. 将版本变更合并到 `main`。
3. 从对应的 `main` 提交创建并推送 Tag：

   ```bash
   git tag v1.5.39
   git push origin v1.5.39
   ```

4. 查看 `Android Release` 工作流。成功后，GitHub Release 会包含带版本号的 APK、`latest` APK 和 `SHA256SUMS.txt`。

Tag 必须严格使用 `vMAJOR.MINOR.PATCH` 格式。去掉 `v` 后的版本必须与 `app/pubspec.yaml` 中 `+` 之前的版本一致。也可以手动运行工作流并输入一个已经存在的 `v*` Tag。

## 密钥轮换

工作流不会自动轮换签名密钥。若密钥泄露，应按照 Android 应用发布策略处理并更新四个 Secrets。无论新旧 keystore，都不能提交到仓库或公开历史。
