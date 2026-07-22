# Changelog

## 1.1.1

- 自查修复：HTTP 超时补齐；known-hosts 删除改 query；文件默认家目录；HOSTKEY 友好提示；health version 对齐
- 设置页版本说明

## 1.1.0

- **固定签名**：debug/release 共用 `android/keystore/sshai-upload.jks`，支持 `pm install -r` 升级不丢数据
- **首次启动向导**：配置 LLM + SSH 主机（可跳过）；设置里可重置向导
- **细节**：启动 Loading 门闩、设置连通性/日志/字号/电池、探针缓存、FGS 保活（1.0 延续）
- 文件(SFTP)、HostKey TOFU、审计筛选、OpenClaw Agent 循环保留

## 1.0.0

- HostKey TOFU、SFTP 文件页、审计筛选
- 前台保活、探针缓存、设置测连通

## 0.9.x

- 日常可用包：FGS、设置诊断、终端字号/resize

## 0.8.x

- OpenClaw 式 Agent tool loop；去掉 rssh 确认墙
- 终端 IME / 键盘样式定型
