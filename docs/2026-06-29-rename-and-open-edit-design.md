# 对味（原「套一套」）改版设计

> 日期：2026-06-29 ｜ App：`~/tao-yi-tao/`（port 8774）｜ 本次三件事：改名 + icon 重做 + 战场判断「打开/编辑」解耦

---

## 1. 背景 / 目标

自用说服-措辞工具 App，原名「套一套·措辞配方」。Ocean 提出三处改动：

1. **改名**：「套一套」太口语、指代不清 → 改为「**对味 · 把话说进他心里**」，同步重做 icon。
2. **icon 重做**：橙红底「套」字 → 青绿底（#1A9E8F）「味」字，换色以标记改版。
3. **战场判断「打开/编辑」解耦**：当前点「打开 / 编辑」直接进可编辑态；改为「打开」=只读态，详情页另给「编辑」按钮才进可编辑态。

---

## 2. 改名落地范围

### 2.1 App 身份（统一改为「对味 · 把话说进他心里」）

| 文件 | 行 | 现状 | 改为 |
|---|---|---|---|
| `index.html` | 6 | `<title>套一套 · 措辞配方</title>` | `<title>对味 · 把话说进他心里</title>` |
| `index.html` | 180 | `<h1>套一套 · 措辞配方</h1>` | `<h1>对味 · 把话说进他心里</h1>` |
| `tao-shell.swift` | 22 | `window.title = "套一套"` | `window.title = "对味"` |
| `tao-shell.swift` | 49 | 退出菜单 `退出套一套` | `退出对味` |
| `tao-shell.swift` | 97 | 错误页 `<h2>套一套 server 没响应</h2>` | `对味` |
| `server.py` | 2 | docstring `套一套·措辞配方 本地服务…` | `对味·措辞配方 本地服务…` |
| `server.py` | 335 | 启动日志 `套一套 server → …` | `对味 server → …` |
| `install.sh` | 11,71,76,81-85,110 | `.app` bundle 名 `套一套`（CFBundleName/DisplayName/Executable/IconFile + 路径 + icns 名 共 ~8 处） | `对味` |
| `install.sh` | 2,14 | 注释/echo `套一套` | `对味` |
| `README.md` | 1,10,28,40 | 标题/正文 `套一套` | `对味`（标题改「对味 · 把话说进他心里」） |
| `start.sh` | 2 | 注释 `套一套 启动脚本` | `对味` |
| `项目/工具/工具中心.md` | 速查表 + launchd 表 + 轻量工具区 | App 名 `套一套` | `对味`（保留旧名一句备注「原套一套」便于检索） |

### 2.2 compose tab / 动词标签（与 App 名解耦，单独处理）

「套一套」一词在界面里还充当**动作动词**，renaming App 不应让这些读起来变怪。Ocean 明确：**去掉"套"字**（"套"工匠感太重），动词改成"话术 / 思路"语感：

| 文件 | 行 | 现状 | 改为 |
|---|---|---|---|
| `index.html` | 187 | tab 按钮 `套一套` | `话术` |
| `index.html` | 452 | 按钮 `用这个套一套` | `用这个思路` |
| `index.html` | 412 | 提示 `…在套一套里用它…` | `…用它…`（去掉"在 X 里"前缀） |
| `index.html` | 849 | 提示 `去「套一套」生成一句话…` | `去「话术」生成一句话…` |
| `index.html` | 223,677 | HTML/JS 注释 `套一套` | `话术`（注释，纯可读性） |
| `index.html` | 878 | 备份文件名 `套一套备份_<date>.json` | `对味备份_<date>.json`（备份归 App 身份，用 App 名） |

### 2.3 非目标（高风险零收益，不动）

- 本地目录 `~/tao-yi-tao/`、GitHub 仓 `tao-yi-tao-public` / `tao-yi-tao-data`、端口 `8774`、env 变量 `TAO_DATA_DIR` —— 改这些要重配 launchd / 重 clone / 可能断多机同步。**对外名换、内部代号留**是干净做法。
- 数据文件 `data.json` 内的历史记录不动。

### 2.4 旧 .app 孤儿处理

`.app` bundle 改名后，旧 `~/Applications/套一套.app` 会成孤儿（Dock 仍指旧的）。落地步骤：跑 `install.sh` 生成新「对味.app」→ **Claude 自动删旧 `套一套.app`**（不留给 Ocean 手动）→ 提示 Ocean 把新 .app 拖回 Dock。

---

## 3. icon 重做

- **现状**：1024px 圆角方块，橙红底（≈#DD5B40）+ 白色「套」字，无源脚本，纯生成 png+icns。
- **改为**：同风格 —— 青绿底 **#1A9E8F** + 白色「**味**」字，圆角方块。
- **生成方式**：PIL 画 1024×1024 PNG（圆角矩形 + 居中「味」字，复用旧版字号/边距比例）→ `iconutil` 转 `.icns`。覆盖 `icon.png` + `icon.icns`。
- 字体：用系统中文字体（PingFang/STHeiti），白色，居中，占比与旧「套」字一致。

---

## 4. 战场判断「打开/编辑」解耦

### 4.1 现状（index.html:500-623）

- 列表卡片：`[打开 / 编辑]` `[删除]`（行 515-516）。
- 点「打开 / 编辑」→ `fwEditId = id; renderFrameworks()` → 进 `renderFwEditor()`，**九问 textarea + 战场名 + 结论 + 理由全可编辑**，按钮 `[保存] [让 Claude 判断] [存判断]`。
- 没有只读层。

### 4.2 改为：只读 + 独立编辑按钮

```
列表卡片：  [打开]  [删除]          ← 「打开/编辑」拆成纯「打开」
   │ 点「打开」
   ▼
详情页（只读态 readonly=true）
   · 战场名 / 九问填答 / 结论 / 理由 —— 全部 disabled，纯展示
   · 顶部按钮：[← 返回列表]  [编辑]  [让 Claude 判断（重仓/观望/撤损）]
   · 隐藏：[保存]、[存判断]（写数据的动作归编辑态）
   · 「让 Claude 判断」保留可用：只拼提示词复制，不改已填数据 ✓（Ocean 确认保留）
   │ 点「编辑」
   ▼
详情页（编辑态 readonly=false）= 现状 renderFwEditor 全量可编辑
   · [← 返回列表]  [保存]  [让 Claude 判断]  [存判断]
```

### 4.3 实现要点

- **状态变量**：新增 `fwReadonly`（bool）。`fwEditId` 语义不变（当前快照 id）。
  - 列表「打开」：`fwEditId=id; fwReadonly=true; renderFrameworks()`
  - 详情「编辑」：`fwReadonly=false; renderFrameworks()`
  - 「+ 新建战场判断」：`fwEditId=""; fwReadonly=false`（新建必然要填，直接编辑态）
- **`renderFwEditor()` 读 `fwReadonly`**：
  - 只读态：所有 `<textarea>` / `<input>` / `<select>` 加 `disabled`；不渲染 `[保存]` `[存判断]`；渲染 `[编辑]` 按钮；保留 `[让 Claude 判断]`、`[← 返回列表]`、各框「复制」按钮（复制只读内容合理）。
  - 编辑态：现状全量不变。
- **「让 Claude 判断」只读态行为**：现状 `$("#fwGen").onclick` 会先 `persist()` 再生成提示词。只读态下**不能 persist**（不写数据）——改为：只读态点击只 `collect()` 当前快照拼提示词复制，跳过 persist；编辑态保持现状（先 persist 再生成）。
- **「复制」按钮**：只读态下 textarea 虽 disabled，但 `.value` 仍可读，`copyf` 逻辑里 `el.select()` 对 disabled 元素可能失效 → 只读态复制改用 `navigator.clipboard.writeText(el.value)` 兜底（不依赖 select）。
- **返回**：`fwBack` 不变（`fwEditId=null`），只读/编辑态都回列表。

### 4.4 验证

- 列表「打开」一条已填快照 → 九问/结论只读、改不动；有「编辑」按钮。
- 只读态点「让 Claude 判断」→ 提示词正确复制、data.json 不变（无新写入）。
- 点「编辑」→ 变可编辑；改一处「保存」→ 持久化、列表更新。
- 「+ 新建战场判断」→ 直接编辑态、可填可存。
- 复制按钮只读态下能复制出内容。

---

## 5. 落地顺序

1. 改名：`index.html` → `tao-shell.swift` → `server.py` → `install.sh` → `README.md` / `start.sh`
2. icon：生成新 png + icns
3. 打开/编辑解耦：改 `index.html` 框架逻辑
4. 重打包 .app（跑 install.sh）+ 删旧孤儿 .app
5. 更新工具中心 SSOT
6. 本机验证（浏览器开 8774 走一遍 §4.4）+ 重启 server
7. git commit（App repo 内；Ocean 要才推/发 Release）

---

## 6. 待 Ocean 最终确认

- §2.2 compose 动词「套话术」是否 OK（唯一开放点；推荐用）。其余均已定。
