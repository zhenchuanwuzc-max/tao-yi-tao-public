# 套一套 · 措辞配方

一个本地小工具：把"我想要"说成"对你有好处"。练自己说服 / 措辞的语感。

核心原则：**别从自己出发——先揣摩对方的心，再用"对他有利"的措辞说。**

## 三个界面

1. **配方库** — 两套配方：「切口」（7 个内置：投其所好 / 儆其所恶 / 选择的自由 / 被认可欲 / 非你不可 / 团队化 / 感谢）+「警句技巧」（自录）。每个配方可写「我的理解」，并一键生成提示词丢给 AI 诊断。
2. **套一套** — ① 对方心思分析（可生成提示词让 AI 帮你分析对方 + 荐配方）→ ② 选配方填空，自动给多个变体说法 → ③ 选一个改成最终版，复制 / 存进复盘。
3. **复盘** — 统计你最常用 / 最少用哪招，事后标效果（成功 / 一般 / 失败），看出自己的说话习惯。

## 架构

- **代码仓（公开）** `tao-yi-tao-public` → 本地 `~/tao-yi-tao/`：`server.py`（Python 标准库 http.server，零依赖）+ `index.html`（纯前端）。
- **数据仓（私有）** `tao-yi-tao-data` → 本地 `~/tao-yi-tao-data/`：`data.json` + `json-merge.py`（JSON-aware union 合并驱动）+ `sync.sh`。
- 数据 `data.json = {recipes, logs, notes}`，每条带 id + 时间戳；多机靠 git 同步，`json-merge.py` 按 id 逐条 union 合并（新增不丢、编辑按时间戳 LWW、删除按 base-diff 传播；notes 的「理解 / 诊断」两字段各自独立合并）。
- server 用环境变量连数据仓：`TAO_DATA_DIR`（默认 `~/tao-yi-tao-data`）、`TAO_PORT`（默认 8774）。

## 装机

```bash
git clone <code-repo> ~/tao-yi-tao
git clone <data-repo> ~/tao-yi-tao-data    # 私有
bash ~/tao-yi-tao/install.sh                # 配 launchd 自启 + 打原生 .app
```

双击 `~/Applications/套一套.app`（或拖进 Dock）即开一个**独立原生窗口**——有自己的 Dock 图标、Cmd+Tab 单独切、跟浏览器隔离。也可直接浏览器开 http://localhost:8774 。

## 设计取向

- 单人自用、数据量小、低频写——所以选「逐条 union 合并、零数据丢失」，而不是更重的 CRDT。
- 标准库 http.server，无 Flask、无 venv、无第三方依赖。
- Dock App = `tao-shell.swift`（macOS 自带 swift + WKWebView 编译的原生壳，零第三方依赖），只负责开窗口连本机 server；server 生命周期归 launchd。无 swiftc 的机器装机时自动回退到 osacompile 浏览器壳。
- AI 诊断 / 分析走"生成提示词 → 复制 → 贴进你的 AI"，不内嵌任何 API key（代码可公开分享）。
