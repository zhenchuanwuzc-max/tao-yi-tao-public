# True Question Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reusable 「真问题筛选」 card to 对味's framework library without changing existing industry-analysis records.

**Architecture:** Keep framework definitions in `index.html` and snapshots in the existing `/frameworks` API. Make the framework definition own its labels, verdicts, empty-state copy, and prompt builder inputs so the shared editor can render either industry analysis or true-question filtering by `fwId`.

**Tech Stack:** Static HTML/CSS/JavaScript, Python standard-library HTTP server, Python `unittest`, localhost port 8774.

## Global Constraints

- Existing `fw_industry` snapshots remain readable and editable without migration.
- New snapshots continue to use `data.json.frameworks`; do not add a backend collection.
- Do not directly edit `~/tao-yi-tao-data/data.json`.
- The new verdicts are exactly `真问题`, `待验证`, and `假问题`.
- Do not represent the classroom statement about cognitive health as a medical conclusion.

---

### Task 1: Add failing framework-contract tests

**Files:**
- Create: `tests/test_true_question_framework.py`
- Test: `tests/test_true_question_framework.py`

**Interfaces:**
- Consumes: `index.html` as the runtime UI source.
- Produces: regression checks for the new definition, per-card creation route, dynamic verdict rendering, and legacy industry copy.

- [ ] **Step 1: Write the failing test**

```python
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
HTML = (ROOT / "index.html").read_text(encoding="utf-8")


class TrueQuestionFrameworkTests(unittest.TestCase):
    def test_true_question_definition_has_six_questions_and_verdicts(self):
        self.assertIn('id:"fw_true_question"', HTML)
        for key in ("impact", "root", "timing", "evidence", "dialogue", "experiment"):
            self.assertIn(f'k:"{key}"', HTML)
        self.assertIn('verdicts:["真问题","待验证","假问题"]', HTML)

    def test_framework_cards_create_their_own_snapshot_type(self):
        self.assertIn("data-fwnew=\"'+fw.id+'\"", HTML)
        self.assertIn('fwNewId=b.dataset.fwnew', HTML)
        self.assertIn('findFw(isNew?fwNewId:snap.fwId)', HTML)

    def test_editor_uses_framework_specific_copy(self):
        self.assertIn('fw.titleLabel', HTML)
        self.assertIn('fw.editorPlaceholder', HTML)
        self.assertIn('fw.verdicts.map', HTML)
        self.assertIn('fw.promptRules', HTML)

    def test_legacy_industry_contract_remains(self):
        self.assertIn('id:"fw_industry"', HTML)
        self.assertIn('verdicts:["重仓","观望","撤损"]', HTML)
        data = (Path.home() / "tao-yi-tao-data" / "data.json").read_text(encoding="utf-8")
        self.assertIn("GGS金物流", data)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest tests/test_true_question_framework.py -v`

Expected: FAIL because `fw_true_question` and dynamic framework metadata do not exist yet.

- [ ] **Step 3: Commit the red test**

```bash
git add tests/test_true_question_framework.py
git commit -m "test: define true-question framework contract"
```

---

### Task 2: Implement framework-specific definitions and shared rendering

**Files:**
- Modify: `index.html:332-349`
- Modify: `index.html:439-646`
- Test: `tests/test_true_question_framework.py`

**Interfaces:**
- Consumes: `BUILTIN_FW`, `findFw(id)`, `fwQuestions(fw)`, and existing `/frameworks` CRUD.
- Produces: `fw_true_question`; `fwNewId: string | null`; shared rendering driven by `fw.titleLabel`, `fw.itemLabel`, `fw.newLabel`, `fw.emptyText`, `fw.editorPlaceholder`, `fw.verdicts`, `fw.promptIntro`, `fw.promptRules`, and `fw.promptAsk`.

- [ ] **Step 1: Extend both framework definitions with complete metadata**

Add the industry metadata while preserving its six existing questions:

```javascript
titleLabel:"战场名（例：金物流 2026-06 / 商品侧复盘）",
titlePlaceholder:"给这次判断起个名",
itemLabel:"我的战场判断",
newLabel:"+ 新建战场判断",
emptyText:'还没有战场判断。点「+ 新建战场判断」，对着天时/地利/人和六问逐条填，填完让 Claude 给“重仓/观望/撤损”的判断。',
editorPlaceholder:"填这个战场的实况…",
genLabel:"让 Claude 判断（重仓/观望/撤损）",
verdicts:["重仓","观望","撤损"],
promptIntro:"我在用「行业分析（天时·地利·人和）」框架判断要不要在一个战场重仓投入，下面是我对各问的填答，请你当教练给判断，别客套：",
promptSubject:"战场",
promptRules:[
  "「前置开关」是前置必要条件：场子若根本不认我产出的这种贡献，直接判‘别进’。但这一格通常是绿灯，别花太多笔墨。",
  "「撬动」我历来做得到（能拉一群人一起干），别误判这一格。",
  "真正的死穴在「复制」：如果只是派活没给能力输入，即使前置开关绿、撬动到位，结论也要往‘观望’压，并直接点破‘你又只是在用团队当手，没在造分身’。",
  "撬动→复制→归属是递进：归属依赖能复制。复制塌，归属保不住。"
],
promptAsk:[
  "天时/地利/人和三层各自绿灯/黄灯/红灯，为什么；",
  "最致命的那一格，尤其复制这一格是给了能力输入，还是只派了活；",
  "结论：重仓 / 观望补缺口 / 撤损换场，一句话拍板；",
  "若观望补缺口，最该先补哪个缺口。"
]
```

Add the second definition:

```javascript
{
  id:"fw_true_question", name:"真问题筛选", desc:"把困惑放进问题池，用事实与对话排除假问题",
  titleLabel:"问题本体（例：我是否需要换部门？）",
  titlePlaceholder:"写下要判断的问题",
  itemLabel:"我的问题判断",
  newLabel:"+ 新建问题判断",
  emptyText:'还没有问题判断。点「+ 新建问题判断」，用六问判断它是真问题、待验证，还是假问题。',
  editorPlaceholder:"写下事实、判断或验证结果…",
  genLabel:"让 Claude 判断（真问题/待验证/假问题）",
  verdicts:["真问题","待验证","假问题"],
  promptIntro:"我在用「真问题筛选」框架检查一个困惑是否值得投入精力。请区分事实、判断和担忧，帮我排除假问题。",
  promptSubject:"问题",
  promptRules:[
    "区分事实与主观担忧，没有事实支持时不要直接判定为真问题。",
    "检查它是否有真实后果、是否只是表象、是否值得现在处理。",
    "尚未验证的命题留在待验证，不强行二分真假。",
    "利用对话反馈排除错误前提，并给出一个最小验证动作。"
  ],
  promptAsk:[
    "事实与主观担忧分别是什么；",
    "它更像根因还是表象，为什么；",
    "结论只能选：真问题 / 待验证 / 假问题，并给一句话理由；",
    "下一步最小验证动作。"
  ],
  layers:[
    {key:"consequence", label:"影响 · 它真的造成后果吗", questions:[
      {k:"impact", q:"如果不解决，会产生什么真实后果？", hint:"写可观察的损失，不写泛泛的不安"}]},
    {key:"diagnosis", label:"诊断 · 它是不是问题本体", questions:[
      {k:"root", q:"它是根因，还是表象？", hint:"继续追问：是什么导致了它"},
      {k:"timing", q:"它现在值得解决吗？", hint:"区分重要但不紧急、现在必须处理、暂时无需投入"},
      {k:"evidence", q:"有什么事实支持它确实存在？", hint:"列数据、事件或重复出现的行为；没有证据就标待验证"}]},
    {key:"falsification", label:"证伪 · 用对话和行动排除假设", questions:[
      {k:"dialogue", q:"和谁聊过？对话排除了哪些错误前提？", hint:"记录对方反馈，以及被推翻的原假设"},
      {k:"experiment", focus:true, q:"下一步最小验证动作是什么？", hint:"设计一个低成本、短周期、能改变判断的动作"}]}
  ]
}
```

- [ ] **Step 2: Make new-record routing explicit per card**

Replace the global fixed new button with card-level buttons rendered from each definition:

```javascript
var fwEditId=null, fwNewId=null;
// inside each card
'<button class="btn sm pri" data-fwnew="'+fw.id+'">'+esc(fw.newLabel)+'</button>'
// event handler
g.querySelectorAll("[data-fwnew]").forEach(function(b){b.onclick=function(){
  fwNewId=b.dataset.fwnew;fwEditId="";fwReadonly=false;renderFrameworks();
};});
```

Hide the old global `#newFwBtn` in framework mode and remove its fixed `fw_industry` handler. In `renderFwEditor`, select the definition with:

```javascript
var fw=findFw(isNew?fwNewId:snap.fwId);
if(!fw){fwEditId=null;fwNewId=null;toast("找不到这个判断框架");renderFrameworks();return;}
```

- [ ] **Step 3: Render labels, verdicts, empty copy, and prompts from framework metadata**

Use `fw.itemLabel`, `fw.emptyText`, `fw.titleLabel`, `fw.titlePlaceholder`, `fw.editorPlaceholder`, and `fw.genLabel` in the shared list/editor. Build verdict options with:

```javascript
var verdictOptions='<option value="">未判断</option>'+fw.verdicts.map(function(v){
  return '<option'+(snap&&snap.verdict===v?' selected':'')+'>'+esc(v)+'</option>';
}).join("");
```

Replace the industry-only `fwPrompt` body with:

```javascript
function fwPrompt(fw,snap){
  var a=snap.answers||{};
  var lines=fwQuestions(fw).map(function(q){return q.q+"\n  → "+(a[q.k]||"（未填）");}).join("\n");
  var rules=fw.promptRules.map(function(x){return "- "+x;}).join("\n");
  var asks=fw.promptAsk.map(function(x,i){return (i+1)+") "+x;}).join("\n");
  return fw.promptIntro+"\n\n【"+fw.promptSubject+"】"+(snap.title||"（未命名）")+"\n\n"+lines+
    "\n\n判断规则（务必遵守）：\n"+rules+"\n\n请直接给：\n"+asks;
}
```

- [ ] **Step 4: Run the focused tests**

Run: `python3 -m unittest tests/test_true_question_framework.py -v`

Expected: 4 tests PASS.

- [ ] **Step 5: Commit the implementation**

```bash
git add index.html tests/test_true_question_framework.py
git commit -m "feat: add true-question filter framework"
```

---

### Task 3: Version, live verification, and compatibility check

**Files:**
- Modify: `VERSION`
- Modify: `README.md:9-11,37-42`
- Test: `tests/test_true_question_framework.py`

**Interfaces:**
- Consumes: completed UI and existing launchd service `com.ocean.tao`.
- Produces: version `0.4.0`, current documentation, and verified localhost behavior.

- [ ] **Step 1: Update release metadata**

Set `VERSION` to `0.4.0`. Update the README to describe three library categories and add:

```markdown
- **0.4.0** — 配方库「框架」新增「真问题筛选」：用后果、根因、时机、事实、对话证伪和最小验证六问，把问题归为真问题 / 待验证 / 假问题；框架新建、文案、结论和 Claude 提示词改为按框架动态渲染，原行业分析历史记录不变。
```

- [ ] **Step 2: Run static and server regression checks**

Run:

```bash
python3 -m unittest discover -s tests -v
python3 -m py_compile server.py
curl -sf http://127.0.0.1:8774/health
```

Expected: all tests PASS; `py_compile` exits 0; health returns `"ok": true` and includes the existing framework count.

- [ ] **Step 3: Restart the local service and verify served content**

Run:

```bash
launchctl kickstart -k gui/$(id -u)/com.ocean.tao
curl -sf http://127.0.0.1:8774/ | rg '真问题筛选|fw_true_question|待验证'
```

Expected: all three strings are present in the served page.

- [ ] **Step 4: Verify existing data was not changed**

Run:

```bash
git -C ~/tao-yi-tao-data status --short
curl -sf http://127.0.0.1:8774/data | python3 -c 'import json,sys; d=json.load(sys.stdin); xs=[x for x in d["frameworks"] if x["fwId"]=="fw_industry"]; print(len(xs), [x["title"] for x in xs])'
```

Expected: no new data-repo change from this feature; output still lists the two `GGS金物流` industry snapshots.

- [ ] **Step 5: Commit release metadata**

```bash
git add VERSION README.md
git commit -m "chore: release 对味 0.4.0"
```
