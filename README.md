# Minis SSH Ops

Minis SSH Ops 是一个面向个人运维场景的 Android SSH 客户端。Flutter 提供主机、终端、文件和 AI Agent 界面，Go 后端在设备本机运行并通过 loopback HTTP 提供 SSH 能力。

## 功能

- 密码和私钥 SSH 认证
- 交互式终端与 SFTP 文件管理
- 主机巡检、命令执行和本地审计记录
- OpenAI 兼容模型接入与多步 Agent 执行
- 命令风险分级、确认门和阻断规则
- SSH 主机密钥 TOFU 校验
- 本机加密存储 SSH 凭据和模型 API Key

## 仓库结构

```text
app/        Flutter 应用和 Android 宿主
backend/    Go 本机服务、SSH、Agent、存储和 HTTP API
docs/       当前产品与技术架构
scripts/    开发、构建和冒烟测试脚本
.github/    CI 和依赖更新配置
```

详细架构见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。脚本说明见 [scripts/README.md](scripts/README.md)。

## 开发

要求：

- Go 1.25+
- Flutter 3.44+
- Android SDK/NDK（构建 APK 时）

运行后端：

```bash
./scripts/run-backend.sh
```

运行后端测试：

```bash
cd backend
go test ./...
```

运行 Flutter 检查：

```bash
cd app
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos
flutter test
```

构建 Android arm64 后端并打 debug APK：

```bash
./scripts/build-go-android.sh
cd app
flutter build apk --debug --target-platform android-arm64
```

## 安全边界

- Go 服务仅监听 `127.0.0.1`。
- 普通 API 使用 `X-Local-Token`，PTY WebSocket 保留 query token 兼容。
- 远程后端地址必须使用 HTTPS；仅 loopback 地址允许 HTTP。
- SSH 密码、私钥、passphrase 和模型 API Key 加密后写入 SQLite。
- 修改和破坏性命令需要明确确认，blocked 命令始终拒绝。
- Android keystore、签名密码、数据库和生成的 Go 二进制不得提交。

完整约束见 [SECURITY.md](SECURITY.md)。

## CI 与发布

`.github/workflows/android.yml` 在 push、PR 和手动触发时执行：

- Go 单元测试和 Linux 后端冒烟
- Android arm64 Go 交叉编译
- Flutter analyze 和单元测试
- debug APK 构建与 SHA-256 校验
- 配置全部签名 Secrets 后的 release APK 构建

未配置签名 Secrets 时只构建 debug APK，不会使用 debug 签名冒充 release。

版本记录见 [CHANGELOG.md](CHANGELOG.md)。
