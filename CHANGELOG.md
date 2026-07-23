## 1.4.13

- E: package-derived backend port; records host filter; probe detail sheet; editor remote size/mode

## 1.4.12

- D: files top bar compact + sort; plan card font; friendly probe errors

## 1.4.11

- A: server fs/move (rename or copy+delete)
- B: fs/read size+binary gates for editor
- C: hosts list search

## 1.4.10

- shared HTTP client
- CPU probe 1s + Go percent + age
- server SFTP fs/copy recursive

## 1.4.9

- 设置页分区重做；终端/Agent/记录字号可调
- Agent 控件与正文字号联动收紧
- 记录页更密列表 + 本地时间

## 1.4.8

- restore post-1.4.7: CPU%%, reasoning, markdown, files top bar, MT editor

## 1.4.7

- 主机：顶栏/卡片密度压缩；CPU/MEM/HDD 指标；MEM/HDD 解析与去重
- Agent：对齐 Minis parts（text/toolUse/toolResult）；流式合并 tool 卡与连续文本；失败默认展开
- 终端：36px 单行顶栏（主机·状态 | 字号 | 键盘 | 更多）
- 底栏高度 64

## 1.4.6

对照真机参考重做（非小改）：

- **主机卡片**：ServerStatus 云探针式 — 绿点 Online + CPU/MEM/HDD 进度条行 + Uptime
- **Agent**：对齐 Minis 会话 — 用户右气泡、tool 顶栏块、Assistant 头像文案、status 转圈
- **文件**：对齐 MT 管理器 — 始终左右双栏、~ 路径条、密列表、底栏 新建/多选/双栏/切栏/更多
- **终端**：控制序列/退格/替换符过滤（延续）

## 1.4.5

- 主机卡片：探针服务式大指标 LOAD/DISK/MEM + 状态 pill
- Agent：Minis 式 tool 卡片头（标签+命令+复制）
- 文件：默认双栏、复制/移动到另一栏、切栏、MT 底栏文案
- 终端：更强控制符剥离，减少方框/tofu

## 1.4.4

- 主机卡片重设计（指标网格 + 状态点）
- 终端字号生效 + 页内 A+/A-
- Agent 输出 Minis 风格：色条块、tool/status/error 分层、可复制
- 设置页分组卡片布局

## 1.4.3

- 文件双栏（MT 风格）：左右独立路径，焦点栏，交换路径
- 多选后复制到另一栏 / 移动 / 删除
- 单栏/双栏切换；底栏操作对焦点栏生效

## 1.4.2

- Agent：默认不乱跑命令；缺事实再 tool；优先单条 run_command
- 去掉首次引导页；设置 API Key 明文显示并回填
- 文件页 MT 风格：底栏操作、多选、路径栏、⋮ 菜单、文件夹优先排序

## 1.4.1

- **长期记忆**：session_memory 滚动摘要 + 要点；旧对话折叠进 SUMMARY/FACTS，不再靠硬截断忘掉
- 最近完整轮次仍保留；ListChat 改为取最近消息
- 记忆刷新在对话结束后异步合并

## 1.4.0

- Agent 上下文：压缩最近 12 轮，截断过长内容，轮次 5
- 模型名：设置/向导可从 `/v1/models` 拉取下拉选择
- 启动：更短健康轮询、hosts/llm 并行加载
- 连接：SSH 池 TTL 延长、拨号默认 12s、更轻探活

## 1.3.3

- 修复 1.3.2 结构问题（JsonEncoder/_friendlyErr）
- SFTP 下载保存到系统 Downloads（MediaStore）
- 配置导出/导入、终端清屏、历史筛选（1.3.2）保留

## 1.3.2

- 配置导出/导入（主机元数据+模型 URL/模型名，不含密码）
- 终端清屏；Agent 历史「仅当前主机」开关
- 1.3.1：HostKey 弹窗、确认卡、会话过滤

## 1.3.1

- HostKey 变更弹窗：清除并重新信任
- Agent 历史按当前主机过滤；确认命令卡片
- 写操作确认/会话持久化（1.3.0）保留

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
