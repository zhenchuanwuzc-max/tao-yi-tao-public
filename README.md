# 对味 · 把话说进他心里

一个本地小工具：把"我想要"说成"对你有好处"。练自己说服 / 措辞的语感。

核心原则：**别从自己出发——先揣摩对方的心，再用"对他有利"的措辞说。**

## 三个界面

1. **配方库** — 三类内容：「切口」（7 个内置）+「警句技巧」（自录）+「框架」（行业分析 / 真问题筛选）。话术配方可记录理解和案例，框架可保存多次判断并生成 AI 诊断提示词。
2. **话术** — ① 对方心思分析（可生成提示词让 AI 帮你分析对方 + 荐配方）→ ② 选配方填空，自动给多个变体说法 → ③ 选一个改成最终版，复制 / 存进复盘。
3. **复盘** — 统计你最常用 / 最少用哪招，事后标效果（成功 / 一般 / 失败），看出自己的说话习惯。

## 架构

- **代码仓（公开）** `tao-yi-tao-public` → 本地 `~/tao-yi-tao/`：`server.py`（Python 标准库 http.server，零依赖）+ `index.html`（纯前端）。
- **数据仓（私有）** `tao-yi-tao-data` → 本地 `~/tao-yi-tao-data/`：`data.json` + `json-merge.py`（JSON-aware union 合并驱动）+ `sync.sh`。
- 数据 `data.json = {recipes, logs, notes, cases, frameworks}`，每条带 id + 时间戳；多机靠 git 同步，`json-merge.py` 按 id 逐条 union 合并（新增不丢、编辑按时间戳 LWW、删除按 base-diff 传播；notes 的「理解 / 诊断」两字段各自独立合并）。
- server 用环境变量连数据仓：`TAO_DATA_DIR`（默认 `~/tao-yi-tao-data`）、`TAO_PORT`（默认 8774）。

## 装机

```bash
git clone <code-repo> ~/tao-yi-tao
git clone <data-repo> ~/tao-yi-tao-data    # 私有
bash ~/tao-yi-tao/install.sh                # 配 launchd 自启 + 打原生 .app
```

双击 `~/Applications/对味.app`（或拖进 Dock）即开一个**独立原生窗口**——有自己的 Dock 图标、Cmd+Tab 单独切、跟浏览器隔离。也可直接浏览器开 http://localhost:8774 。

## 设计取向

- 单人自用、数据量小、低频写——所以选「逐条 union 合并、零数据丢失」，而不是更重的 CRDT。
- 标准库 http.server，无 Flask、无 venv、无第三方依赖。
- Dock App = `tao-shell.swift`（macOS 自带 swift + WKWebView 编译的原生壳，零第三方依赖），只负责开窗口连本机 server；server 生命周期归 launchd。无 swiftc 的机器装机时自动回退到 osacompile 浏览器壳。
- AI 诊断 / 分析走"生成提示词 → 复制 → 贴进你的 AI"，不内嵌任何 API key（代码可公开分享）。

## 更新记录

- **0.5.0** — 「真问题筛选」改为极简 Excel 纵表：每题一张两列表，单元格直接填写，显式保存；支持下拉判断、未保存内容生成 Claude 提示词，并保留行业分析原界面与历史记录。
- **0.4.0** — 配方库「框架」新增「真问题筛选」：用后果、根因、时机、事实、对话证伪和最小验证六问，把问题归为真问题 / 待验证 / 假问题；框架新建、文案、结论和 Claude 提示词改为按框架动态渲染，原行业分析历史记录不变。
- **0.3.0** — 改名「套一套 · 措辞配方」→「对味 · 把话说进他心里」（旧名口语、指代不清）；icon 换青绿底「味」字；compose tab/动词去掉"套"字（→「话术」/「用这个思路」）；「战场判断」打开/编辑解耦：打开=只读态，详情页另给「编辑」按钮才可改（只读态保留「让 Claude 判断」生成提示词）。内部目录/仓名/端口/env（`tao-yi-tao` / 8774 / `TAO_DATA_DIR`）不变。
- **0.2.0** — Dock App 从「osacompile 甩浏览器开标签」改成 Swift+WKWebView 原生独立窗口（独立 Dock 图标 + Cmd+Tab 单独切 + 跟浏览器隔离，零依赖；无 swiftc 自动回退浏览器壳）；加主菜单快捷键 Cmd+R 刷新 / Cmd+W 关窗 / Cmd+Q 退出；修复切 tab 时居中列因滚动条宽度差左右跳动。
- **0.1.0** — 首版：标准库 server + 公开代码仓/私有数据仓双仓 + 多机 git 逐条 union 合并；配方库（切口 7 个内置 + 警句技巧）/ 套一套填空 / 复盘统计三界面。
