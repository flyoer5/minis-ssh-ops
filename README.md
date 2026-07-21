# Minis SSH Ops / SSH AI Agent

个人用 **Android AI SSH 运维**（Flutter 原生 UI + 本机 Go 后端）。

本仓库以 [ssh-ai-agent](https://github.com/flyoer5/ssh-ai-agent) 为底，并补齐：

- 命令风险分级（read / write / destructive / blocked）与确认门
- 自然语言 Agent：`/v1/agent/plan` + `/v1/agent/exec-step`
- 审计日志 `/v1/audit` + App「记录」页
- 主机健康探测 `/v1/hosts/{id}/probe`

## 结构

```text
backend/     Go：SSH、加密 SQLite、loopback HTTP
app/         Flutter：主机 / AI 运维 / 记录 / 设置
scripts/     启动、Android 交叉编译
.github/     APK CI
docs/        产品与架构
```

## 本机跑后端

```bash
export PATH=/usr/local/go/bin:$PATH
cd backend && go build -o bin/server ./cmd/server
SSH_AI_DATA_DIR=$HOME/.ssh-ai-agent SSH_AI_PORT=17890 ./bin/server
```

冒烟：

```bash
./scripts/smoke-api.sh
```

## 打 APK（GitHub Actions）

推送后自动构建；或 Actions → **Android APK** → Run workflow。

本地（有 Flutter 时）：

```bash
./scripts/build-go-android.sh
cd app && flutter pub get && flutter build apk --debug --target-platform android-arm64
```

## 安全

- 仅监听 `127.0.0.1`
- `X-Local-Token` 鉴权
- 主机密钥 / API Key AES 加密入库
- 高危命令拦截；变更类需 `confirmed: true`
