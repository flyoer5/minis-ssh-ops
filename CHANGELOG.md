## 1.3.0

- Agent 会话持久化（重启仍在）
- 设置：写操作需确认开关（可选）
- 文件页路径书签 ~ /etc /var/log /tmp /home
- 1.2.2：SFTP 重命名/下载、主机编辑菜单

## 1.2.2

- 修复 SFTP 菜单编译（补全重命名/下载实现）
- 主机卡片增加 ⋮ 菜单入口（编辑/刷新/删除）
- 会话标题时间格式修正

## 1.2.1

- 稳定性：Agent 可取消进行中请求；多会话归档/历史
- SFTP：重命名、下载(复制内容)、mkdir/删/上传保留
- 主机长按菜单：编辑 / 刷新 / 删除

## 1.2.0

- Agent SSE 流式（tool/结果即时上屏）
- SFTP：mkdir/删除/文本上传；列表解析绝对路径

# Changelog

## 1.1.2

- SSH 连接池：探针/Agent/SFTP 复用连接降延迟
- 设置：管理 HostKey（查看指纹/删除重信）
- 终端：粘贴按钮
- Agent：处理中提示更清晰

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
