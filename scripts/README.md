# Scripts

仓库保留的脚本都用于当前开发或 CI 流程。

| 脚本 | 用途 |
|------|------|
| `run-backend.sh` | 构建并启动本机 Go 后端；设置 `REBUILD=1` 可强制重建 |
| `smoke-api.sh` | 使用数据目录中的 `local.token` 检查 health、鉴权主机列表和未授权响应 |
| `build-go-android.sh` | 为 Android arm64 交叉编译 Go 后端，并复制到 Flutter assets 与 jniLibs |

## 环境变量

- `SSH_AI_DATA_DIR`：后端数据目录，默认 `$HOME/.ssh-ai-agent`
- `SSH_AI_PORT`：loopback 监听端口，默认 `17890`
- `REBUILD=1`：运行 `run-backend.sh` 时强制重新构建

## 生成文件

`build-go-android.sh` 生成的二进制均被 `.gitignore` 排除，不应提交：

```text
app/android/app/src/main/assets/go/ssh-ai-agent
app/android/app/src/main/jniLibs/arm64-v8a/libssh_ai_agent.so
app/assets/go/ssh-ai-agent-arm64
```
