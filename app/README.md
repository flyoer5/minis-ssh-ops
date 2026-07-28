# Flutter App

此目录包含 Minis SSH Ops 的 Flutter UI 和 Android 宿主。Android 应用启动内嵌 Go 后端，Flutter 通过 `127.0.0.1` 上的本机 HTTP API 与其通信。

## 目录

```text
lib/api/       HTTP 客户端与后端地址校验
lib/backend/   Android 内嵌后端生命周期
lib/models/    页面和 API 数据模型
lib/pages/     主机、Agent、终端、文件、记录和设置页面
lib/state/     应用状态、会话和 UI 偏好
lib/theme/     主题与颜色
lib/widgets/   通用组件
test/          Flutter 单元和组件测试
android/       Android 宿主、前台服务和 Gradle 配置
assets/        图标、终端页面和构建期 Go 资源
```

## 常用命令

```bash
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos
flutter test
flutter run
```

构建 APK 前，先从仓库根目录运行：

```bash
./scripts/build-go-android.sh
```

该脚本生成以下被 `.gitignore` 排除的文件：

- `android/app/src/main/assets/go/ssh-ai-agent`
- `android/app/src/main/jniLibs/arm64-v8a/libssh_ai_agent.so`
- `assets/go/ssh-ai-agent-arm64`

## Android 签名

本地签名配置参考 `android/key.properties.example`。不要提交 `key.properties`、`.jks` 或 `.keystore` 文件。CI release 构建所需 Secrets 见仓库根目录的 [SECURITY.md](../SECURITY.md)。
