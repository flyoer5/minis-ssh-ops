# Minis SSH Ops

面向个人运维的 **本地私有 AI SSH 运维** 核心服务（`opsd`）。

- **Go 后台**：SSH / 加密 SQLite / OpenAI 兼容 Agent / 本机 HTTP API  
- **调试 UI**：`web/static` 单页（后续由 Flutter 替换）  
- **目标交付**：静态 arm64 二进制内嵌进 Flutter APK（单一安装包）

## 快速启动（本机 opsd）

```bash
cd /var/minis/workspace/minis-ssh-ops
CGO_ENABLED=0 go build -ldflags='-s -w' -o bin/opsd ./cmd/opsd/

OPSD_TOKEN=devtoken123 ./bin/opsd \
  -addr 127.0.0.1:18765 \
  -data ./data \
  -web ./web/static
```

浏览器打开：`http://127.0.0.1:18765/`  
请求头：`X-Ops-Token: <token>`（本机 `/api/token` 可在 loopback 引导取 token）

## Flutter APK

### 推荐：GitHub Actions（无需本机 Flutter）

见 **[docs/GITHUB_APK.md](docs/GITHUB_APK.md)**。

1. 推送到 GitHub  
2. Actions → **Build Android APK** → 下载 Artifact  

### 本机有 Flutter 时

```bash
./app/scripts/prepare_assets.sh
cd app && flutter pub get && flutter build apk --release --target-platform android-arm64
```

详见 [`app/README.md`](app/README.md)。

## 架构

```
Flutter / Web UI  --HTTP 127.0.0.1-->  opsd
                                        ├─ storage  SQLite + AES-GCM 密钥字段
                                        ├─ sshx     连接池 / 命令执行
                                        └─ agent    风险分级 + LLM 规划 + 逐步确认执行
```

## API 摘要

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/health` | 健康检查 |
| GET | `/api/token` | **仅 loopback** 返回 token |
| GET/POST | `/api/hosts` | 列表 / 新增主机（密码私钥 AES 存储） |
| GET/DELETE | `/api/hosts/{id}` | 详情 / 删除 |
| POST | `/api/hosts/{id}/connect` | SSH 连通性测试 |
| POST | `/api/hosts/{id}/disconnect` | 断开连接池 |
| GET/PUT | `/api/llm` | 模型配置（Key 脱敏返回） |
| POST | `/api/exec` | 执行命令（write/destructive 需 `confirmed`） |
| POST | `/api/probe` | 只读健康快照 |
| POST | `/api/agent/plan` | LLM 生成分步计划 |
| POST | `/api/agent/exec-step` | 执行计划中一步 |
| GET | `/api/audit` | 审计日志 |
| POST | `/api/fs/list` | SFTP 列目录 `{host_id,path}` |
| POST | `/api/fs/read` | 读文件（默认最大 2MiB） |
| POST | `/api/fs/write` | 写文件（需 `confirmed`） |
| POST | `/api/fs/mkdir` | 建目录（需确认） |
| POST | `/api/fs/remove` | 删除（需确认；禁 `/`） |
| POST | `/api/fs/stat` | 文件信息 |
| WS | `/api/pty?token=&host_id=&cols=&rows=` | 交互 PTY（二进制输出；JSON 控制：input/resize） |

### 风险策略

| 级别 | 行为 |
|------|------|
| `read` | 可直接执行 |
| `write` | 需 `confirmed: true` |
| `destructive` | 需确认 |
| `blocked` | 拒绝（如 `rm -rf /`、`mkfs`、`curl\|sh`） |

## 数据文件

`data/`（默认）：

- `ops.db` — SQLite  
- `master.key` — 32 字节设备主密钥（AES-GCM）

主机密码/私钥、LLM API Key 均加密入库，API 列表不回传明文密钥。

## 开发路线

- [x] Go MVP：存储 / SSH / 风险门 / Agent 规划 / HTTP / Web 调试页  
- [x] pure-Go SQLite（`modernc.org/sqlite`）+ `CGO_ENABLED=0` 静态链  
- [x] SFTP 文件管理（list/read/write/mkdir/remove/stat）  
- [x] 交互式 PTY 终端（WebSocket + xterm.js 调试页）  
- [x] Flutter 壳骨架（WebView + 原生主机页 + 拉起 opsd / jniLibs）  
- [ ] 有 Flutter SDK 的机器上出正式签名 APK  
- [ ] 主密码派生密钥（可选生物解锁）  
- [ ] 前台服务保活 / 电池优化引导落地  

## 构建说明

**推荐（Android / 无 CGO）：**

```bash
CGO_ENABLED=0 go build -ldflags='-s -w' -o bin/opsd ./cmd/opsd/
# aarch64 静态二进制，约 12–15MB（strip 后更小）
```

依赖：`modernc.org/sqlite`、`golang.org/x/crypto/ssh`、`github.com/pkg/sftp`。

## 安全注意

1. 默认只绑 `127.0.0.1`，勿对公网监听。  
2. 生产请设置强 `OPSD_TOKEN`。  
3. Agent 的 `risk` 以服务端 `Classify` 为准，不信任模型自报。  
4. HostKey 当前为 `InsecureIgnoreHostKey`（个人设备 MVP）；后续应做 TOFU。
