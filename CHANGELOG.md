## 1.5.0

### 高度自定义
- Agent: 模型温度 (0–2, 直接传backend)、自定义提示词 (suffix)、工具轮数 1–99
- Settings: 温度滑块 + 预设、自定义提示词编辑框
- Prefs: 导出/导入/重置含新字段
- Backend: wire temperature + customPrompt to LLM calls

## 1.4.51

### MaxRounds
- Fully open: 1–99 freely set (no hard clamp); default 12
- Preset chips: 4/8/12/24/40/64

### Polish
- Terminal: _muted/_fg aliases → AppColors
- Minor text alignment

## 1.4.50

### Polish
- Settings/Agent/UI: concise Chinese captions and explanations
- Files: transfer bar cancel; download error hint
- Hosts: probe data detail text
- Records: 暂无执行记录

### MaxRounds
- Range 3–32 (was 3–12), default 12; preset chips (8/12/16/24/32)

## 1.4.49

### Settings
- Agent: max tool rounds (3–12), show reasoning, collapse tools, auto-scroll, enter-to-send, keep keyboard, haptic
- Display: host auto-probe interval (0–300s)
- Prefs export/import/reset include new keys

### Wiring
- Backend chat/stream accept maxRounds (clamp 3–12)
- Agent UI respects prefs (scroll, enter, keyboard, reasoning, tool collapse, haptic)
- Hosts page periodic probe when interval > 0

## 1.4.48

### Bugfix
- Agent: stop no longer falls back to batch chat (was re-running the whole turn)
- Agent: turn generation guard drops stale SSE after stop/new chat
- Agent: pendingConfirm tool cards not paired with later tool_results
- Agent: runAgentStep double-tap debounce; seal pending toolUse after confirm
- Agent: open tools marked interrupted on stop; clearer model error strings
- Terminal: connection generation guard (stale WS events after reconnect)

## 1.4.47

### Agent
- Confirm card: risk badge, copy, 运行并继续 (exec + resume agent with result)
- 全部运行 for multi-step confirms; hide synthetic continue messages
- Tool cards: 运行中 spinner, 中文 tool names, pending-confirm state
- NEEDS_CONFIRM dedup + mark open toolUse; better confirmWrites setting copy
- Error bubbles copyable; retry skips synthetic confirm follow-ups
- System prompt: 机枢 identity, noninteractive flags, no re-run after confirm
- Empty chips refreshed

## 1.4.46

- Settings: Chinese thinking levels; about shows backend feature chips
- Hosts: probe age 秒/分钟/小时/天前
- Records: pull-to-refresh; export prefix jishu-audit-
- Agent sessions: richer empty state

## 1.4.45

- Hosts: Online/Offline → 在线/离线
- Agent sessions: relative times (刚刚 / n 分钟前 / 今天)
- Settings: richer empty states for TOFU known-hosts and long-term memory

## 1.4.44

- Settings: version chip shows live backendVersion (no more hard-coded 1.4.9)
- Hosts menu: open Agent / Terminal / Files for selected host
- Terminal & Files: empty-host CTA with 去选主机

## 1.4.43

- Agent: quick-start chips on empty chat; jump-to-bottom when scrolled up
- Hosts: title shows online/total count
- Terminal: connecting banner (AppColors); disconnected banner themed
- Records: relative-friendly list times (刚刚 / n 分钟前 / 今天 HH:MM)

## 1.4.42

- Brand: rename to 机枢 (launcher label, Material title, FGS notification, settings about)
- New launcher icon (dark navy + cyan terminal hub) + adaptive icons
- Hosts: long-press menu → 复制地址
- Agent empty copy: 向 机枢 发消息; settings tagline SSH 运维 Agent · 主机枢纽

## 1.4.41

- Agent: top host/backend status strip + 选主机
- Files: empty-directory illustration
- Records: empty state distinguishes no data vs no search hits (clear filters)

## 1.4.40

- Hosts: empty state with add CTA
- Terminal: reconnect on app resume; disconnected banner with one-tap 重连

## 1.4.39

- Files multi-select: 全选 / 反选
- Agent: trim live transcript to 200 messages; busy hint 可点停止

## 1.4.38

- Settings: 流式 Markdown toggle; probe concurrency 1–6 slider
- Hosts: probe workers use probeConcurrency pref
- Agent: optional live MD while streaming; session content truncated on save (12k)

## 1.4.37

- Agent: auto-follow stream to bottom when near end (won't yank if user scrolled up)
- Files: download cap 8MB→32MB; clearer too-large snackbar

## 1.4.36

- Agent polish: empty-state jump to hosts; retry last after stop/error
- Interrupted bubbles tagged「已中断」; stop status clearer
- Continues 1.4.35: ErrorWidget recovery, safer add-host (not installed by default)

## 1.4.35

- Fix: friendly ErrorWidget instead of stuck red crash screen
- Fix: add-host uses new host id; probe failure stays on list with snackbar + detail
- Fix: ANSI dim uses Color.value (no Color.red crash path)
- Agent: richer empty state; surface send errors; block send while busy

## 1.4.34

- Files: path favorites (star + chips, long-press copy still)
- Terminal: scrollback search with highlights; larger buffer (~400KB)
- Continues 1.4.33 polish (CSI strip, path jump, records search)

## 1.4.33

- Polish: stronger terminal CSI strip (private modes, alt screen, keypad)
- Files: tap path bar to type absolute path and jump
- Records: keyword search (command/stdout/stderr/host)
- Download progress labels clearer (pull → write phone)

## 1.4.32

- Terminal: strip DEC private CSI (ESC[?2004h bracketed paste) so prompt is not prefixed with ?2004h

## 1.4.31

- Hosts: password **or PEM private key** (+ optional passphrase) in add/edit sheet; card shows key/password icon
- Structure: `agent_widgets.dart` / `settings_widgets.dart` parts; `host_editor.dart`
- Settings & Records: `wantKeepAlive: false` to free memory off-tab
- Slim backend status strip (replace tall MaterialBanner)
- Test: host auth body assembly unit test
- Structure: extract `AgentChatController` mixin (~850 lines streaming/session/tool pairing)
- AppState slimmed to bootstrap/hosts/probe/LLM/config (~500 lines)

## 1.4.30

- Perf: throttle Agent stream UI notifies (~33ms) for assistant/reasoning deltas
- Cleanup: remove dead AppState terminal buffer / runTerminal / runExec paths (~110 lines)
- Files: ListView `itemExtent: 48` + cacheExtent for large directories
- ApiClient.dispose + AppState.dispose
- Tests: Go `risk.Classify` unit tests; CI runs `go test` + `flutter test`
- CI: PR builds debug only; release APK on main/push / workflow_dispatch
- Host cards: settings toggle **精简** (MEM+HDD only) via `hostCardCompact`
- Probe refresh concurrency limited to 3
- AppState: extract `UiPrefs` mixin (fonts/nav/host card/confirmWrites)
- Cancel agent flushes pending stream notify

## 1.4.29

- Nav: bottom bar 56; settings switch **底部栏 / 左上角菜单** (`navMode`)
- Split models: `AgentSession`, `ProbeSummary` out of AppState (re-export kept)
- Agent: first-class `ChatKind.toolUse` / `toolResult` (+ legacy meta.part)

## 1.4.28

- K: stream plain-text body (Markdown only after final) to reduce MD reparse jitter
- K: reasoning_merge pure helpers + unit tests; final/stream dedupe by compact text
- K: reasoning_delta keeps leading spaces (no trim on raw field)
- K: cancel path logs session/host when SSE client stops

## 1.4.27

- UI/editor font size prefs (hosts+files lists, editor default)
- Editor: synced line gutter, undo/redo, compact toolbar, case-sensitive find, scroll-to-match

## 1.4.26

- Fix: reasoning no longer duplicated (stream without spaces + final with spaces merged as one)

## 1.4.25

- Real stop: cancel request context aborts LLM stream + SSH session (SIGKILL best-effort)
- SSE write stops on client disconnect; skip memory/done after cancel

## 1.4.24

- Fix: final reasoning no longer creates a second thinking card under the answer
- Reasoning coalesced per turn (above reply)

## 1.4.23

- Fix: do not TrimSpace reasoning stream tokens (spaces between words)
- Reasoning panel: soft wrap body instead of monospace glue look

## 1.4.22

- Blink streaming cursor; terminal copy plain/raw; probe retry+copy; settings feature chips
- includes 1.4.21 stream coalesce fix

## 1.4.21

- Fix: streaming assistant_delta + final no longer creates duplicate bubbles

## 1.4.20

- Agent stop UI (app bar + composer + busy row) and streaming cursor
- Files copy/move/download progress banner

## 1.4.19

- Big: OpenAI token streaming (assistant_delta / reasoning_delta) into Agent SSE
- Big: ANSI color terminal (SGR / 256 / truecolor subset)

## 1.4.18

- J: system share for audit CSV; finish AppColors cleanup; probe/theme unit tests

## 1.4.17

- I: AppColors rollout across pages
- I: audit CSV to Downloads + clipboard
- I: agent sessions grouped by host

## 1.4.16

- H: agent session rename/delete sheet polish
- H: editor read-only + UTF-8 status
- H: shared AppColors + buildAppTheme

## 1.4.15

- G: denser multi-select bar; audit CSV export; settings show derived backend port

## 1.4.14

- F: HostKey manager sheet (list/delete/clear + TOFU help)
- F: long-term memory list/view/delete APIs + settings UI

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
