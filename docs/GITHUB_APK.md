# 用 GitHub Actions 编译 APK

本机（Minis PRoot）不必装 Flutter。把仓库推到 GitHub 后，用 Actions 出 **arm64 release APK**。

## 一次性准备

### 1. 创建 GitHub 仓库

在 GitHub 新建空仓库（例如 `minis-ssh-ops`），不要勾选自动加 README（本地已有）。

### 2. 推送代码

在能访问 git 的环境（电脑或本机若已装 `git` + 网络）：

```bash
cd /path/to/minis-ssh-ops

git init
git add .
git status   # 确认没有 data/、bin/、master.key、opsd 大二进制、libopsd.so
# 应看到: .github/workflows/android-apk.yml, cmd/, internal/, app/lib/, web/static/ 等

git commit -m "feat: opsd + flutter shell + apk workflow"

git branch -M main
git remote add origin https://github.com/<你的用户名>/minis-ssh-ops.git
git push -u origin main
```

**Minis 本机**：若 `git push` 需登录，可用 [GitHub PAT](https://github.com/settings/tokens) 作 HTTPS 密码，或在电脑上 push。不要把 `data/master.key`、真实 API Key 提交进库。
若使用 SSH：

```bash
git remote add origin git@github.com:<你的用户名>/minis-ssh-ops.git
git push -u origin main
```

### 3. 触发构建

任选其一：

| 方式 | 操作 |
|------|------|
| 自动 | 推送到 `main` / `master`（改了 app/cmd/internal 等路径会触发） |
| 手动 | GitHub → **Actions** → **Build Android APK** → **Run workflow** |
| 发版 | 打 tag：`git tag v0.1.0 && git push origin v0.1.0`（会额外挂到 Release） |

### 4. 下载 APK

1. 打开仓库 **Actions**，进入最新成功的 workflow  
2. 底部 **Artifacts** → `minis-ssh-ops-apk`  
3. 解压得到：
   - `minis-ssh-ops-*-arm64.apk`
   - `SHA256SUMS.txt`

手机安装：允许「未知来源」后安装该 APK（当前为 **debug 签名**，仅自用）。

## 工作流做什么

```
ubuntu-latest
  ├─ go build GOOS=linux GOARCH=arm64 → bin/opsd
  ├─ flutter create（补齐 gradle wrapper）
  ├─ prepare_assets.sh → jniLibs/libopsd.so + assets
  ├─ flutter build apk --release --target-platform android-arm64
  └─ upload-artifact
```

文件：`.github/workflows/android-apk.yml`

## 常见失败

| 现象 | 处理 |
|------|------|
| `assets/opsd/opsd_arm64` not found | 确认 `prepare_assets.sh` 在 `flutter build` 之前执行 |
| Gradle / SDK 错误 | 看日志；Flutter stable 升级后偶发，可 pin `flutter-action` 的 `flutter-version` |
| 签名 | 默认 debug 签名；上架需配置 keystore secrets（可再加一步） |
| 安装后闪退 | 用 `adb logcat` 看 opsd 是否可执行；确认手机为 **arm64** |

## 可选：正式签名

在仓库 Secrets 增加：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

再在 workflow 里 decode keystore 并配置 `signingConfigs.release`（需要时再改 `app/android/app/build.gradle`）。

## 与本机 opsd 的关系

| 场景 | 用法 |
|------|------|
| 开发调试 API / Agent | 本机 `./bin/opsd` + 浏览器 |
| 给手机装独立 App | Actions 产物 APK |

两者共用同一套 Go 代码与 Web UI。
