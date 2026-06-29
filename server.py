#!/usr/bin/env python3
"""对味·措辞配方 本地服务（JSON-as-truth + git 同步，Python 标准库 http.server）

数据：data.json = {updated, recipes:[], logs:[], notes:[]}
  每条 item 带 id + created_at/updated_at；notes 另带 u_at/d_at（u/d 各自 LWW）。
  内置 7 配方在 index.html 代码里（BUILTIN），不进 data.json——只有用户自加配方进 recipes。

端点：
  GET    /              index.html
  GET    /data          整个 doc
  GET    /health        {ok, counts}
  POST   /recipes       新增用户配方
  PATCH  /recipes/<id>  编辑
  DELETE /recipes/<id>  删（连带删该 recipe 的 note）
  POST   /logs          新增复盘记录
  PATCH  /logs/<id>     改（如 effect）
  DELETE /logs/<id>     删
  PUT    /notes/<rid>   upsert 理解/诊断 {u?,d?}（各自打时间戳）
  DELETE /notes/<rid>   删
  POST   /import        {recipes,logs,notes} 整体替换（迁移用）

端口 env TAO_PORT(默认 8774)；数据 env TAO_DATA_DIR(默认 ~/tao-yi-tao-data)。
范式照搬 quotes-app：_atomic_write + 锁内 read-modify-write + schedule_sync 防抖。
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
import uuid
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

try:
    from zoneinfo import ZoneInfo
    TZ = ZoneInfo("Asia/Shanghai")
except Exception:
    TZ = None

PORT = int(os.environ.get("TAO_PORT", 8774))
DATA_DIR = os.environ.get("TAO_DATA_DIR", "")
if not DATA_DIR:
    for _c in ("~/tao-yi-tao-data", "~/tao-yi-tao"):
        _p = os.path.expanduser(_c)
        if os.path.isdir(_p):
            DATA_DIR = _p
            break
    else:
        DATA_DIR = "~/tao-yi-tao-data"
DATA_DIR = os.path.expanduser(DATA_DIR)
DATA_FILE = os.path.join(DATA_DIR, "data.json")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
COLLECTIONS = ("recipes", "logs", "notes", "cases", "frameworks")

INDEX_HTML = "<h1>index.html not loaded</h1>"


def load_index():
    global INDEX_HTML
    try:
        with open(os.path.join(SCRIPT_DIR, "index.html"), encoding="utf-8") as f:
            INDEX_HTML = f.read()
    except Exception as e:
        print(f"index.html load failed: {e}", file=sys.stderr)


load_index()


def now_iso():
    return (datetime.now(TZ) if TZ else datetime.now()).isoformat(timespec="seconds")


_lock = threading.RLock()


def read_data():
    if not os.path.exists(DATA_FILE):
        return {"updated": now_iso(), "recipes": [], "logs": [], "notes": []}
    with open(DATA_FILE, encoding="utf-8") as f:
        d = json.load(f)
    for k in COLLECTIONS:
        if not isinstance(d.get(k), list):
            d[k] = []
    return d


def _atomic_write(d):
    os.makedirs(DATA_DIR, exist_ok=True)
    d["updated"] = now_iso()
    tmp = tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=DATA_DIR, delete=False, suffix=".tmp")
    try:
        json.dump(d, tmp, ensure_ascii=False, indent=2)
        tmp.flush()
        os.fsync(tmp.fileno())
        tmp.close()
        os.replace(tmp.name, DATA_FILE)
    except Exception:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass
        raise


_sync_timer = None
_sync_lock = threading.Lock()


def schedule_sync(delay=5.0):
    global _sync_timer
    sh = os.path.join(DATA_DIR, "sync.sh")
    if not os.path.exists(sh):
        return
    with _sync_lock:
        if _sync_timer is not None:
            _sync_timer.cancel()
        _sync_timer = threading.Timer(delay, _run_sync, args=[sh])
        _sync_timer.daemon = True
        _sync_timer.start()


def _run_sync(sh):
    try:
        subprocess.Popen(["/bin/bash", sh], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, cwd=DATA_DIR, start_new_session=True)
    except Exception:
        pass


def _find(arr, i):
    for x in arr:
        if x.get("id") == i:
            return x
    return None


# ---------- 业务操作（锁内 read-modify-write）----------

def add_item(coll, obj):
    ts = now_iso()
    obj = dict(obj)
    obj["id"] = obj.get("id") or str(uuid.uuid4())
    obj["created_at"] = ts
    obj["updated_at"] = ts
    with _lock:
        d = read_data()
        d[coll] = [x for x in d[coll] if x.get("id") != obj["id"]]
        if coll == "logs":
            d[coll].insert(0, obj)
        else:
            d[coll].append(obj)
        _atomic_write(d)
    schedule_sync()
    return obj


def patch_item(coll, i, fields):
    fields = {k: v for k, v in (fields or {}).items() if k not in ("id", "created_at")}
    with _lock:
        d = read_data()
        t = _find(d[coll], i)
        if t is None:
            return None
        t.update(fields)
        t["updated_at"] = now_iso()
        _atomic_write(d)
    schedule_sync()
    return t


def delete_item(coll, i):
    with _lock:
        d = read_data()
        before = len(d[coll])
        d[coll] = [x for x in d[coll] if x.get("id") != i]
        deleted = len(d[coll]) < before
        if coll == "recipes":
            d["notes"] = [x for x in d["notes"] if x.get("id") != i]
            d["cases"] = [x for x in d["cases"] if x.get("recipeId") != i]
        if deleted:
            _atomic_write(d)
    if deleted:
        schedule_sync()
    return deleted


def upsert_note(rid, u=None, dval=None):
    with _lock:
        data = read_data()
        t = _find(data["notes"], rid)
        ts = now_iso()
        if t is None:
            t = {"id": rid, "u": "", "u_at": None, "d": "", "d_at": None}
            data["notes"].append(t)
        if u is not None:
            t["u"] = u
            t["u_at"] = ts
        if dval is not None:
            t["d"] = dval
            t["d_at"] = ts
        _atomic_write(data)
    schedule_sync()
    return t


def delete_note(rid):
    with _lock:
        d = read_data()
        before = len(d["notes"])
        d["notes"] = [x for x in d["notes"] if x.get("id") != rid]
        deleted = len(d["notes"]) < before
        if deleted:
            _atomic_write(d)
    if deleted:
        schedule_sync()
    return deleted


def replace_all(recipes, logs, notes, cases=None):
    ts = now_iso()

    def stamp(x):
        x = dict(x)
        x["id"] = x.get("id") or str(uuid.uuid4())
        x.setdefault("created_at", ts)
        x["updated_at"] = ts
        return x

    nn = []
    for x in (notes or []):
        x = dict(x)
        if not x.get("id"):
            continue
        x.setdefault("u", "")
        x.setdefault("d", "")
        x["u_at"] = ts if x.get("u") else None
        x["d_at"] = ts if x.get("d") else None
        nn.append(x)
    with _lock:
        d = read_data()
        d["recipes"] = [stamp(x) for x in (recipes or [])]
        d["logs"] = [stamp(x) for x in (logs or [])]
        d["notes"] = nn
        d["cases"] = [stamp(x) for x in (cases or [])]
        _atomic_write(d)
    schedule_sync()
    return read_data()


# ---------- 检查更新（git 多机：fetch 比对 → ff-only pull → 重启）----------
# 逻辑参照每日待办，但套一套是「git 仓 + localhost 套壳」，更新走 git 不走 Release。

LAUNCHD_LABEL = "com.ocean.tao"
_upd_lock = threading.Lock()
_upd = {"status": "idle", "error": None}   # idle | pulling | restarting | error


def _set_upd(**kw):
    with _upd_lock:
        _upd.update(kw)


def get_upd():
    with _upd_lock:
        return dict(_upd)


def _git(args, cwd, timeout=20):
    """跑 git，禁交互（GIT_TERMINAL_PROMPT=0）；非 git 目录/超时/异常统一回 returncode=1。"""
    if not cwd or not os.path.isdir(os.path.join(cwd, ".git")):
        class _R:
            returncode, stdout, stderr = 1, "", "no repo"
        return _R()
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    try:
        return subprocess.run(["git"] + args, cwd=cwd, env=env,
                              capture_output=True, text=True, timeout=timeout)
    except Exception as e:
        class _R:
            returncode, stdout, stderr = 1, "", str(e)
        return _R()


def read_version():
    try:
        with open(os.path.join(SCRIPT_DIR, "VERSION"), encoding="utf-8") as f:
            return f.read().strip()
    except Exception:
        return "0.0.0"


def _repo_status(repo):
    """fetch origin/main 后回 (behind 提交数, 远端最新 commit 标题, 是否有未提交改动)"""
    _git(["fetch", "origin", "main"], repo, timeout=20)
    behind = _git(["rev-list", "--count", "HEAD..origin/main"], repo).stdout.strip()
    subj = _git(["log", "-1", "--format=%s", "origin/main"], repo).stdout.strip()
    dirty = bool(_git(["status", "--porcelain"], repo).stdout.strip())
    try:
        behind = int(behind or 0)
    except ValueError:
        behind = 0
    return behind, subj, dirty


def check_update():
    code_behind, code_subj, code_dirty = _repo_status(SCRIPT_DIR)
    data_behind, _, data_dirty = _repo_status(DATA_DIR)
    remote_ver = _git(["show", "origin/main:VERSION"], SCRIPT_DIR).stdout.strip()
    return {
        "current": read_version(),
        "latest_ver": remote_ver or read_version(),
        "behind": code_behind,
        "data_behind": data_behind,
        "latest_msg": code_subj,
        "dirty": code_dirty or data_dirty,
    }


def apply_update():
    """ff-only pull 代码仓 + 数据仓，再 detached 重启 launchd 服务（kickstart -k）。"""
    code_behind, _, code_dirty = _repo_status(SCRIPT_DIR)
    data_behind, _, data_dirty = _repo_status(DATA_DIR)
    if code_dirty or data_dirty:
        raise RuntimeError("本地有未提交改动，已暂停自动更新（避免覆盖你的改动）")
    if not code_behind and not data_behind:
        return {"ok": True, "started": False, "note": "已是最新"}

    def _worker():
        try:
            _set_upd(status="pulling", error=None)
            if code_behind:
                r = _git(["pull", "--ff-only", "origin", "main"], SCRIPT_DIR, timeout=90)
                if r.returncode != 0:
                    raise RuntimeError("代码仓 pull 失败：" + (r.stderr or "")[:140])
            if data_behind:
                r = _git(["pull", "--ff-only", "origin", "main"], DATA_DIR, timeout=90)
                if r.returncode != 0:
                    raise RuntimeError("数据仓 pull 失败：" + (r.stderr or "")[:140])
            _set_upd(status="restarting")
            # kickstart -k 会杀掉当前 server 并重启；detached(start_new_session) 让它在自身被杀后仍存活。
            subprocess.Popen(
                ["/bin/bash", "-c",
                 f"sleep 1; launchctl kickstart -k gui/{os.getuid()}/{LAUNCHD_LABEL}"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        except Exception as e:
            _set_upd(status="error", error=str(e))

    threading.Thread(target=_worker, daemon=True).start()
    return {"ok": True, "started": True}


# ---------- HTTP ----------

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", f"{ctype}; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False)
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.wfile.write(body)

    def _read_body(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        if not n:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            return {}

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            self._send(200, INDEX_HTML, "text/html")
        elif path == "/data":
            self._send(200, read_data())
        elif path == "/health":
            d = read_data()
            self._send(200, {"ok": True, "counts": {k: len(d[k]) for k in COLLECTIONS}})
        elif path == "/check-update":
            try:
                self._send(200, check_update())
            except Exception as e:
                self._send(200, {"error": str(e)})
        elif path == "/update-progress":
            self._send(200, get_upd())
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        path = urlparse(self.path).path
        b = self._read_body()
        if path == "/recipes":
            self._send(200, add_item("recipes", b))
        elif path == "/logs":
            self._send(200, add_item("logs", b))
        elif path == "/cases":
            self._send(200, add_item("cases", b))
        elif path == "/frameworks":
            self._send(200, add_item("frameworks", b))
        elif path == "/import":
            self._send(200, replace_all(b.get("recipes"), b.get("logs"), b.get("notes"), b.get("cases")))
        elif path == "/apply-update":
            try:
                self._send(200, apply_update())
            except Exception as e:
                self._send(200, {"ok": False, "error": str(e)})
        else:
            self._send(404, {"error": "not found"})

    def do_PATCH(self):
        parts = urlparse(self.path).path.strip("/").split("/")
        b = self._read_body()
        if len(parts) == 2 and parts[0] in ("recipes", "logs", "frameworks"):
            t = patch_item(parts[0], parts[1], b)
            self._send(200 if t else 404, t or {"error": "not found"})
        else:
            self._send(404, {"error": "not found"})

    def do_PUT(self):
        parts = urlparse(self.path).path.strip("/").split("/")
        b = self._read_body()
        if len(parts) == 2 and parts[0] == "notes":
            self._send(200, upsert_note(parts[1], b.get("u"), b.get("d")))
        else:
            self._send(404, {"error": "not found"})

    def do_DELETE(self):
        parts = urlparse(self.path).path.strip("/").split("/")
        if len(parts) == 2 and parts[0] in ("recipes", "logs", "cases", "frameworks"):
            self._send(200, {"deleted": delete_item(parts[0], parts[1])})
        elif len(parts) == 2 and parts[0] == "notes":
            self._send(200, {"deleted": delete_note(parts[1])})
        else:
            self._send(404, {"error": "not found"})


def main():
    print(f"对味 server → http://localhost:{PORT}   data={DATA_DIR}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
