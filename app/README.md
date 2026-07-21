# Minis SSH Ops — Flutter 壳

Android 应用壳：启动时解压/拉起内嵌 **opsd**（Go 静态二进制），UI 以 WebView 加载本机 `http://127.0.0.1:18765/`，并提供原生主机列表页。

## 目录

```
app/
  lib/                  Dart 源码
  assets/opsd/          opsd_arm64（prepare 生成）
  assets/web/           调试 Web UI（prepare 生成）
  android/              Gradle 工程（arm64-v8a）
  scripts/prepare_assets.sh
```

## 构建 APK（需本机 Flutter + Android SDK）

```bash
# 0. 环境
# flutter doctor
# Android SDK / cmdline-tools / platform 34+ / NDK（按 flutter 提示）

# 1. 从仓库根准备二进制与 Web
cd /path/to/minis-ssh-ops
./app/scripts/prepare_assets.sh

# 2. 拉依赖并打包
cd app
flutter pub get
flutter build apk --release --target-platform android-arm64
# 产物: build/app/outputs/flutter-apk/app-release.apk
```

### 调试

```bash
# 若电脑已 adb 连真机
flutter run -d <deviceId>
```

本 Minis PRoot 环境 **通常没有完整 Flutter/Android SDK**，请在装有 Flutter 的机器上执行 `flutter build apk`。

## 运行时行为

1. `OpsdService.start()`  
   - 优先执行 `nativeLibraryDir/libopsd.so`（jniLibs 打包）  
   - 否则从 asset 解压 `opsd_arm64` 到应用 support 目录并 `chmod 755`  
2. 启动：`OPSD_TOKEN=... ./opsd -addr 127.0.0.1:18765 -data <support>/opsd-data -web <support>/opsd-web`  
3. 健康检查通过后打开 WebView  
4. Token 存 `SharedPreferences`，并注入页面 `localStorage.opsd_token`

## 权限与注意

- `INTERNET` + 明文 localhost（network security config）  
- 建议引导用户关闭电池优化（关于页已提示）  
- 仅 `arm64-v8a`  
- 首次 release 使用 debug 签名，上架前请换成正式 keystore  

## 与 opsd API 对齐

原生页当前实现：主机列表 / 添加 / 连接 / 探测。  
完整终端、SFTP、Agent 走 WebView 内同一套调试 UI（与桌面浏览器版相同）。
