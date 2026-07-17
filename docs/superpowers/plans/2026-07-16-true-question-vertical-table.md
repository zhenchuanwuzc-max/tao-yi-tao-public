# True Question Vertical Table Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the true-question card/editor flow with an inline, Excel-like vertical two-column table while preserving the industry framework unchanged.

**Architecture:** Keep all UI code in `index.html` and all saved records in the existing `/frameworks` collection. `renderFrameworks()` delegates only `fw_true_question` to a focused renderer; each row collects its own DOM values and explicitly POSTs or PATCHes on Save.

**Tech Stack:** Static HTML/CSS/JavaScript, Python standard-library HTTP server, Python `unittest`, localhost port 8774.

## Global Constraints

- Use the approved B layout: white background, thin gray lines, shallow gray label column, one purple accent line, no large purple blocks.
- Fields run vertically; do not add horizontal scrolling.
- Industry analysis and its two GGS snapshots remain unchanged.
- Edits never autosave. Save is explicit per question.
- New drafts do not touch `/frameworks` until Save.
- Reuse `/frameworks`; do not change `server.py` or the sync model.
- Verdicts remain exactly `真问题 / 待验证 / 假问题`.

---

### Task 1: Add failing vertical-table contract tests

**Files:**
- Create: `tests/test_true_question_vertical_table.py`
- Test: `tests/test_true_question_vertical_table.py`

**Interfaces:**
- Consumes: `index.html` as the shipped application UI.
- Produces: regression checks for the custom renderer, field schema, explicit save flow, and preserved industry renderer.

- [ ] **Step 1: Write the failing tests**

```python
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
HTML = (ROOT / "index.html").read_text(encoding="utf-8")


class TrueQuestionVerticalTableTests(unittest.TestCase):
    def test_true_question_has_custom_vertical_renderer(self):
        self.assertIn("function renderTrueQuestionSection(fw)", HTML)
        self.assertIn('fw.id==="fw_true_question"', HTML)
        self.assertIn('class="tq-sheet"', HTML)
        self.assertIn('class="tq-grid"', HTML)

    def test_all_vertical_fields_are_present(self):
        self.assertIn('data-tq="title"', HTML)
        for field in (
            "raisedAt", "impact", "root", "timing", "evidence",
            "dialogue", "experiment", "deadline", "verdict", "reason",
        ):
            self.assertIn(f'key:"{field}"', HTML)
        self.assertIn('data-tq="\'+field.key+\'"', HTML)
        self.assertIn('["根因","表象","暂不确定"]', HTML)
        self.assertIn('["现在解决","稍后解决","无需解决","待判断"]', HTML)
        self.assertIn('["真问题","待验证","假问题"]', HTML)

    def test_save_is_explicit_and_supports_post_and_patch(self):
        self.assertIn("function trueQuestionBodyFromRow(row)", HTML)
        self.assertIn("function saveTrueQuestion(row)", HTML)
        self.assertIn('api("POST","/frameworks",body)', HTML)
        self.assertIn('api("PATCH","/frameworks/"+id,body)', HTML)
        self.assertIn('if(!body.title)', HTML)

    def test_unsaved_prompt_and_cancel_are_supported(self):
        self.assertIn("function trueQuestionPrompt(fw,body)", HTML)
        self.assertIn('data-tqaction="prompt"', HTML)
        self.assertIn('data-tqaction="cancel"', HTML)

    def test_industry_editor_contract_remains(self):
        self.assertIn('id:"fw_industry"', HTML)
        self.assertIn("function renderFwEditor()", HTML)
        self.assertIn('data-fwopen', HTML)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the focused test and verify red**

Run: `python3 -m unittest tests/test_true_question_vertical_table.py -v`

Expected: five failures because the custom vertical renderer does not exist.

- [ ] **Step 3: Commit the red tests**

```bash
git add tests/test_true_question_vertical_table.py
git commit -m "test: define true-question vertical table contract"
```

---

### Task 2: Implement the approved B vertical table

**Files:**
- Modify: `index.html:141-183`
- Modify: `index.html:373-407`
- Modify: `index.html:578-706`
- Test: `tests/test_true_question_vertical_table.py`
- Test: `tests/test_true_question_framework.py`

**Interfaces:**
- Consumes: global `frameworks`, `api(method,path,body)`, `fwPrompt`, `toast`, and the `fw_true_question` definition.
- Produces: `renderTrueQuestionSection(fw)`, `trueQuestionBodyFromRow(row)`, `saveTrueQuestion(row)`, and `trueQuestionPrompt(fw, body)`.

- [ ] **Step 1: Add the minimal approved CSS**

Add these focused classes to `index.html` without changing industry styles:

```css
.tq-section{margin-top:14px}
.tq-head{display:flex;align-items:flex-end;justify-content:space-between;gap:12px;margin-bottom:12px}
.tq-title{font-size:16px;font-weight:650}.tq-sub{font-size:12px;color:var(--muted)}
.tq-list{display:flex;flex-direction:column;gap:14px}
.tq-sheet{background:var(--surface);border:.5px solid var(--line2);border-radius:9px;overflow:hidden}
.tq-sheet-head{padding:12px 14px;border-bottom:2px solid var(--accent);display:flex;justify-content:space-between;gap:12px;align-items:center}
.tq-grid{display:grid;grid-template-columns:minmax(128px,25%) minmax(0,1fr)}
.tq-label,.tq-cell{padding:8px 11px;border-bottom:.5px solid var(--line)}
.tq-label{background:var(--surface2);color:var(--muted);font-size:12px}
.tq-cell input,.tq-cell select,.tq-cell textarea{border:0;border-radius:0;padding:0;background:transparent;box-shadow:none}
.tq-cell textarea{min-height:46px}.tq-cell input:focus,.tq-cell select:focus,.tq-cell textarea:focus{box-shadow:none}
.tq-foot{padding:9px 12px;background:var(--surface2);display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap}
.tq-updated{font-size:11px;color:var(--hint)}
.tq-verdict[data-v="真问题"]{color:var(--bad)}.tq-verdict[data-v="待验证"]{color:var(--warn)}.tq-verdict[data-v="假问题"]{color:var(--ok)}
@media(max-width:560px){.tq-grid{grid-template-columns:116px minmax(0,1fr)}.tq-label,.tq-cell{padding:8px}}
```

- [ ] **Step 2: Route the true-question definition to its custom section**

Inside `renderFrameworks()`, render industry cards normally and append the special section:

```javascript
var html=BUILTIN_FW.map(function(fw){
  if(fw.id==="fw_true_question")return renderTrueQuestionSection(fw);
  var snaps=snapsOf(fw.id);
  var snapHtml=snaps.length?snaps.map(function(s){
    return '<div class="snap">'+
      '<div class="st"><span class="sname">'+esc(s.title||("（未命名"+fw.promptSubject+"）"))+'</span>'+
        (s.verdict?'<span class="sv" data-v="'+esc(s.verdict)+'">'+esc(s.verdict)+'</span>':'<span class="sv">未判断</span>')+'</div>'+
      (s.reason?'<div class="sreason">'+esc(s.reason)+'</div>':'')+
      '<div class="sops"><button class="btn sm" data-fwopen="'+s.id+'">打开</button>'+
      '<button class="btn sm ghost" data-fwdel="'+s.id+'">删除</button></div></div>';
  }).join(""):'<div class="ct" style="font-size:12px;color:var(--hint)">'+esc(fw.emptyText)+'</div>';
  return '<div class="fwcard"><div class="fwtop"><div><div class="fwname">'+esc(fw.name)+'</div>'+
    '<div class="fwdesc">'+esc(fw.desc)+'</div></div>'+
    '<button class="btn sm pri" data-fwnew="'+fw.id+'">'+esc(fw.newLabel)+'</button></div>'+
    '<div class="fwsnaps"><div class="sh">'+esc(fw.itemLabel)+' ('+snaps.length+')</div>'+snapHtml+'</div></div>';
}).join("");
g.innerHTML=html;
g.querySelectorAll("[data-fwnew]").forEach(function(b){b.onclick=function(){
  fwNewId=b.dataset.fwnew;fwEditId="";fwReadonly=false;renderFrameworks();
};});
g.querySelectorAll("[data-fwopen]").forEach(function(b){b.onclick=function(){
  fwEditId=b.dataset.fwopen;fwReadonly=true;renderFrameworks();
};});
g.querySelectorAll("[data-fwdel]").forEach(function(b){b.onclick=function(){
  if(confirm("删除这个判断？")){var id=b.dataset.fwdel;frameworks=frameworks.filter(function(s){return s.id!==id;});api("DELETE","/frameworks/"+id);renderFrameworks();}
};});
bindTrueQuestionEvents(g);
```

- [ ] **Step 3: Render each question as a vertical two-column sheet**

Use the fixed field order below:

```javascript
var TRUE_QUESTION_FIELDS=[
  {key:"raisedAt",label:"提出日期",type:"date"},
  {key:"impact",label:"不解决的真实后果",type:"textarea"},
  {key:"root",label:"根因还是表象",type:"select",options:["根因","表象","暂不确定"]},
  {key:"timing",label:"当前时机",type:"select",options:["现在解决","稍后解决","无需解决","待判断"]},
  {key:"evidence",label:"事实证据",type:"textarea"},
  {key:"dialogue",label:"对话证伪",type:"textarea"},
  {key:"experiment",label:"下一步最小验证",type:"textarea"},
  {key:"deadline",label:"验证截止日",type:"date"},
  {key:"verdict",label:"结论",type:"select",options:["真问题","待验证","假问题"]},
  {key:"reason",label:"一句话理由",type:"textarea"}
];
```

`renderTrueQuestionSection(fw)` sorts saved records by `updated_at`, prepends one unsaved draft when `trueQuestionDraft` is present, and returns a `.tq-section`. Each `.tq-sheet` includes `data-tqid` for saved rows or `data-tqdraft="1"` for the draft; every input carries `data-tq="<field>"`.

- [ ] **Step 4: Implement explicit save without losing failed input**

Collect one row with:

```javascript
function trueQuestionBodyFromRow(row){
  function value(key){var el=row.querySelector('[data-tq="'+key+'"]');return el?(el.value||"").trim():"";}
  return {
    fwId:"fw_true_question",fwVersion:3,title:value("title"),raisedAt:value("raisedAt"),
    answers:{impact:value("impact"),root:value("root"),timing:value("timing"),evidence:value("evidence"),dialogue:value("dialogue"),experiment:value("experiment")},
    deadline:value("deadline"),verdict:value("verdict"),reason:value("reason")
  };
}
```

Save with:

```javascript
function saveTrueQuestion(row){
  var body=trueQuestionBodyFromRow(row),id=row.dataset.tqid||"";
  if(!body.title){toast("问题不能为空");return;}
  var request=id?api("PATCH","/frameworks/"+id,body):api("POST","/frameworks",body);
  request.then(function(saved){
    if(id)frameworks=frameworks.map(function(x){return x.id===id?Object.assign({},x,body,saved):x;});
    else frameworks.push(saved);
    trueQuestionDraft=null;toast("已保存");renderFrameworks();
  });
}
```

Do not catch and rerender on failure; the existing `api()` displays the error and the current DOM remains intact.

- [ ] **Step 5: Bind new, cancel, delete, save, and prompt actions**

Bind the section buttons after every render. New sets `trueQuestionDraft={raisedAt:new Date().toISOString().slice(0,10)}` and rerenders. Cancel clears only the draft. Delete confirms and calls the existing DELETE endpoint. Prompt collects the current row without saving:

```javascript
function trueQuestionPrompt(fw,body){
  var snap={title:body.title,answers:body.answers};
  return fwPrompt(fw,Object.assign({},snap,{deadline:body.deadline,verdict:body.verdict,reason:body.reason}));
}

function bindTrueQuestionEvents(g){
  var add=g.querySelector("[data-tqnew]");
  if(add)add.onclick=function(){
    if(trueQuestionDraft){toast("先保存或取消当前新问题");return;}
    trueQuestionDraft={raisedAt:new Date().toISOString().slice(0,10)};renderFrameworks();
  };
  g.querySelectorAll("[data-tqaction]").forEach(function(button){
    button.onclick=function(){
      var row=button.closest(".tq-sheet"),action=button.dataset.tqaction,id=row.dataset.tqid||"";
      if(action==="save"){saveTrueQuestion(row);return;}
      if(action==="prompt"){
        var fw=findFw("fw_true_question");copy(trueQuestionPrompt(fw,trueQuestionBodyFromRow(row)));return;
      }
      if(action==="cancel"){trueQuestionDraft=null;renderFrameworks();return;}
      if(action==="delete"&&id&&confirm("删除这个问题？")){
        api("DELETE","/frameworks/"+id).then(function(){
          frameworks=frameworks.filter(function(x){return x.id!==id;});renderFrameworks();
        });
      }
    };
  });
}
```

The prompt button calls `copy(trueQuestionPrompt(fw,trueQuestionBodyFromRow(row)))` and leaves the row unchanged.

- [ ] **Step 6: Run all tests and JavaScript syntax verification**

Run:

```bash
python3 -m unittest discover -s tests -v
node -e 'const fs=require("fs");const h=fs.readFileSync("index.html","utf8");new Function(h.match(/<script>([\s\S]*)<\/script>/)[1])'
```

Expected: all tests PASS; Node exits 0.

- [ ] **Step 7: Commit the implementation**

```bash
git add index.html tests/test_true_question_vertical_table.py
git commit -m "feat: render true questions as vertical tables"
```

---

### Task 3: Release, live UI verification, and regression check

**Files:**
- Modify: `VERSION`
- Modify: `README.md:7-12,39-45`
- Test: `tests/test_true_question_vertical_table.py`
- Test: `tests/test_true_question_framework.py`

**Interfaces:**
- Consumes: completed UI and launchd service `com.ocean.tao`.
- Produces: version `0.5.0`, updated documentation, and a verified local application.

- [ ] **Step 1: Update release metadata**

Set `VERSION` to `0.5.0` and prepend:

```markdown
- **0.5.0** — 「真问题筛选」改为极简 Excel 纵表：每题一张两列表，单元格直接填写，显式保存；支持下拉判断、未保存内容生成 Claude 提示词，并保留行业分析原界面与历史记录。
```

- [ ] **Step 2: Verify tests, source syntax, and server health**

Run:

```bash
python3 -m unittest discover -s tests -v
python3 -m py_compile server.py
node -e 'const fs=require("fs");const h=fs.readFileSync("index.html","utf8");new Function(h.match(/<script>([\s\S]*)<\/script>/)[1])'
launchctl kickstart -k gui/$(id -u)/com.ocean.tao
curl -sf http://127.0.0.1:8774/health
```

Expected: tests PASS, syntax checks exit 0, and health returns `"ok": true` with `frameworks: 2` before the first true-question save.

- [ ] **Step 3: Verify data compatibility**

Run:

```bash
curl -sf http://127.0.0.1:8774/data | python3 -c 'import json,sys;d=json.load(sys.stdin);xs=[x for x in d["frameworks"] if x["fwId"]=="fw_industry"];assert len(xs)==2;print([x["title"] for x in xs])'
git -C ~/tao-yi-tao-data status --short
```

Expected: two `GGS金物流` records remain and the data repo is clean before UI write testing.

- [ ] **Step 4: Verify the live app visually**

In the native 对味 app: refresh, open 框架, confirm industry card and both GGS rows remain; confirm true-question section is a vertical two-column sheet with no horizontal scrollbar; create a draft, fill all select types, generate a prompt without saving, cancel, and confirm `/data` still contains zero `fw_true_question` records.

- [ ] **Step 5: Commit release metadata**

```bash
git add VERSION README.md
git commit -m "chore: release 对味 0.5.0"
```
