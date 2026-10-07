"""主流程冒烟测试：临时目录 + 随机端口起真实 server.py 子进程，走 HTTP 验证。

隔离保证（不碰真实数据仓、不碰网络）：
- TAO_DATA_DIR 指向临时目录；子进程 HOME 也指向临时目录（连 ~ 兜底都进不了真实数据仓）。
- 临时数据目录里不放 sync.sh → server.schedule_sync() 直接 return，不会 git 同步/推送。
- 不调用 /check-update、/apply-update（这两个会 git fetch / 重启 launchd）。
- 启动后校验 server 打印的 data= 路径就是临时目录，对不上立即失败。
"""
import atexit
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "server.py"
HTTP_TIMEOUT = 5          # 单次请求上限（秒）
START_TIMEOUT = 8         # 等 server 起来的上限（秒）
COLLECTIONS = ("recipes", "logs", "notes", "cases", "frameworks", "profiles")

_live = set()             # 兜底：解释器退出时杀掉所有还活着的子进程 + 删临时目录
_tmpdirs = set()


def _cleanup_all():
    for srv in list(_live):
        srv.stop()
    for d in list(_tmpdirs):
        shutil.rmtree(d, ignore_errors=True)


atexit.register(_cleanup_all)


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Server:
    """一个指向临时数据目录的 server.py 子进程。"""

    def __init__(self, root_tmp, seed=None):
        self.root_tmp = root_tmp
        self.home = os.path.join(root_tmp, "home")
        self.data_dir = os.path.join(root_tmp, "data")
        os.makedirs(self.home, exist_ok=True)
        os.makedirs(self.data_dir, exist_ok=True)
        if seed is not None:
            with open(os.path.join(self.data_dir, "data.json"), "w", encoding="utf-8") as f:
                json.dump(seed, f, ensure_ascii=False)
        self.proc = None
        self.port = None

    @property
    def base(self):
        return f"http://127.0.0.1:{self.port}"

    def start(self):
        assert not os.path.exists(os.path.join(self.data_dir, "sync.sh")), "临时数据目录不许有 sync.sh"
        last_err = None
        for _ in range(3):                      # 端口被抢占就换一个重试
            self.port = free_port()
            env = dict(os.environ, HOME=self.home, TAO_PORT=str(self.port),
                       TAO_DATA_DIR=self.data_dir, PYTHONUNBUFFERED="1")
            self.proc = subprocess.Popen([sys.executable, str(SERVER)], env=env,
                                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                         text=True, cwd=self.root_tmp)
            _live.add(self)
            banner = self._wait_ready()
            if banner is not None:
                assert f"data={self.data_dir}" in banner, f"server 没连到临时数据目录: {banner!r}"
                return
            last_err = self.stop()
        raise RuntimeError(f"server 起不来: {last_err}")

    def _wait_ready(self):
        deadline = time.time() + START_TIMEOUT
        while time.time() < deadline:
            if self.proc.poll() is not None:
                return None
            try:
                with urllib.request.urlopen(self.base + "/health", timeout=1) as r:
                    if r.status == 200:
                        return self.proc.stdout.readline()   # 启动横幅（先于监听打印，此时必已在管道里）
            except Exception:
                time.sleep(0.1)
        return None

    def stop(self):
        out = ""
        if self.proc is not None:
            if self.proc.poll() is None:
                self.proc.terminate()
                try:
                    out, _ = self.proc.communicate(timeout=3)
                except subprocess.TimeoutExpired:
                    self.proc.kill()
                    out, _ = self.proc.communicate(timeout=3)
            else:
                out, _ = self.proc.communicate(timeout=3)
            self.proc = None
        _live.discard(self)
        return out

    # ---- HTTP helpers ----
    def req(self, method, path, body=None):
        data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
        r = urllib.request.Request(self.base + path, data=data, method=method,
                                   headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(r, timeout=HTTP_TIMEOUT) as resp:
                raw = resp.read().decode("utf-8")
                return resp.status, resp.headers.get("Content-Type", ""), raw
        except urllib.error.HTTPError as e:
            return e.code, e.headers.get("Content-Type", ""), e.read().decode("utf-8")

    def j(self, method, path, body=None):
        code, _, raw = self.req(method, path, body)
        return code, json.loads(raw)


SEED = {
    "recipes": [{"id": "seed-recipe", "name": "种子配方", "created_at": "2026-01-01T00:00:00",
                 "updated_at": "2026-01-01T00:00:00"}],
}


class SmokeBase(unittest.TestCase):
    def new_server(self, seed=None):
        tmp = tempfile.mkdtemp(prefix="tao-smoke-")
        _tmpdirs.add(tmp)
        srv = Server(tmp, seed=seed)

        def _done():
            srv.stop()
            shutil.rmtree(tmp, ignore_errors=True)
            _tmpdirs.discard(tmp)

        self.addCleanup(_done)
        srv.start()
        return srv


class SmokeTests(SmokeBase):
    def setUp(self):
        self.srv = self.new_server(seed=SEED)

    def test_01_index_is_html(self):
        code, ctype, raw = self.srv.req("GET", "/")
        self.assertEqual(code, 200)
        self.assertIn("text/html", ctype)
        self.assertIn("<html", raw.lower())
        self.assertIn("对味", raw)

    def test_02_read_data_and_health(self):
        code, d = self.srv.j("GET", "/data")
        self.assertEqual(code, 200)
        for k in COLLECTIONS:                       # 空/缺字段也要补全成 list（0.6.0 修过的坑）
            self.assertIsInstance(d[k], list, k)
        self.assertEqual([r["id"] for r in d["recipes"]], ["seed-recipe"])
        code, h = self.srv.j("GET", "/health")
        self.assertTrue(h["ok"])
        self.assertEqual(h["counts"]["recipes"], 1)

    def test_03_core_write_log_then_read_back(self):
        """最核心写入：新增一条复盘记录 → 再读到 → 改效果 → 删除。"""
        code, log = self.srv.j("POST", "/logs", {"text": "把话说进他心里 ✓", "recipeId": "seed-recipe"})
        self.assertEqual(code, 200)
        self.assertTrue(log["id"])
        _, d = self.srv.j("GET", "/data")
        got = [x for x in d["logs"] if x["id"] == log["id"]]
        self.assertEqual(len(got), 1)
        self.assertEqual(got[0]["text"], "把话说进他心里 ✓")        # 中文无损
        code, p = self.srv.j("PATCH", "/logs/" + log["id"], {"effect": "成功"})
        self.assertEqual((code, p["effect"]), (200, "成功"))
        _, d = self.srv.j("GET", "/data")
        self.assertEqual([x["effect"] for x in d["logs"] if x["id"] == log["id"]], ["成功"])
        code, r = self.srv.j("DELETE", "/logs/" + log["id"])
        self.assertEqual((code, r["deleted"]), (200, True))
        _, d = self.srv.j("GET", "/data")
        self.assertFalse([x for x in d["logs"] if x["id"] == log["id"]])

    def test_04_recipe_note_framework_profile_writes(self):
        code, rec = self.srv.j("POST", "/recipes", {"name": "新配方"})
        self.assertEqual(code, 200)
        code, n = self.srv.j("PUT", "/notes/" + rec["id"], {"u": "我的理解", "d": "我的诊断"})
        self.assertEqual((n["u"], n["d"]), ("我的理解", "我的诊断"))
        # 真问题筛选的保存路径：POST 新建 → PATCH 更新
        code, fw = self.srv.j("POST", "/frameworks", {"fwId": "fw_true_question", "title": "某问题"})
        self.assertEqual(code, 200)
        code, fw2 = self.srv.j("PATCH", "/frameworks/" + fw["id"], {"verdict": "真问题"})
        self.assertEqual((code, fw2["verdict"], fw2["title"]), (200, "真问题", "某问题"))
        code, prof = self.srv.j("POST", "/profiles", {"name": "老王"})
        self.assertEqual(code, 200)
        _, d = self.srv.j("GET", "/data")
        self.assertIn(rec["id"], [x["id"] for x in d["recipes"]])
        self.assertIn(rec["id"], [x["id"] for x in d["notes"]])
        self.assertIn(fw["id"], [x["id"] for x in d["frameworks"]])
        self.assertIn(prof["id"], [x["id"] for x in d["profiles"]])
        # 删配方连带删它的 note
        self.srv.j("DELETE", "/recipes/" + rec["id"])
        _, d = self.srv.j("GET", "/data")
        self.assertNotIn(rec["id"], [x["id"] for x in d["notes"]])

    def test_05_patch_missing_is_404(self):
        code, _ = self.srv.j("PATCH", "/logs/not-exist", {"effect": "x"})
        self.assertEqual(code, 404)
        code, _, _ = self.srv.req("GET", "/no-such-path")
        self.assertEqual(code, 404)

    def test_06_export_backup_shape_and_import_roundtrip(self):
        """导出备份 = 前端用 GET /data 的 6 个 collection 拼 JSON；这里验数据完整 + /import 能还原。"""
        self.srv.j("POST", "/logs", {"text": "导出前的记录"})
        self.srv.j("POST", "/profiles", {"name": "导出画像"})
        _, exported = self.srv.j("GET", "/data")
        json.dumps(exported, ensure_ascii=False)                     # 可序列化 = 备份文件有效
        for k in COLLECTIONS:
            self.assertIn(k, exported)
        # 部分备份（老备份只有 recipes）不能把别的 collection 清空
        code, _ = self.srv.j("POST", "/import", {"recipes": [{"id": "only-one", "name": "唯一"}]})
        self.assertEqual(code, 200)
        _, d = self.srv.j("GET", "/data")
        self.assertEqual([x["id"] for x in d["recipes"]], ["only-one"])
        self.assertEqual(len(d["logs"]), 1)
        self.assertEqual(len(d["profiles"]), 1)
        # 整包还原
        body = {k: exported[k] for k in COLLECTIONS}
        self.srv.j("POST", "/import", body)
        _, d = self.srv.j("GET", "/data")
        for k in COLLECTIONS:
            self.assertEqual([x["id"] for x in d[k]], [x["id"] for x in exported[k]], k)

    def test_07_no_sync_or_git_side_effects(self):
        """写入后临时数据目录里没有 sync.sh / .git（即 schedule_sync 没有可跑的东西）。"""
        self.srv.j("POST", "/logs", {"text": "x"})
        self.assertFalse(os.path.exists(os.path.join(self.srv.data_dir, "sync.sh")))
        self.assertFalse(os.path.exists(os.path.join(self.srv.data_dir, ".git")))
        self.assertTrue(os.path.exists(os.path.join(self.srv.data_dir, "data.json")))


class RestartTests(SmokeBase):
    def test_data_survives_restart(self):
        srv = self.new_server(seed=None)                 # 从空库起（顺带验空库启动不 KeyError）
        code, h = srv.j("GET", "/health")
        self.assertEqual(h["counts"], {k: 0 for k in COLLECTIONS})
        _, log = srv.j("POST", "/logs", {"text": "重启前写的"})
        _, rec = srv.j("POST", "/recipes", {"name": "重启前的配方"})
        srv.stop()
        with self.assertRaises(Exception):               # 确认真的停了
            urllib.request.urlopen(srv.base + "/health", timeout=1)
        srv.start()                                      # 同一个数据目录重起（新端口）
        _, d = srv.j("GET", "/data")
        self.assertIn(log["id"], [x["id"] for x in d["logs"]])
        self.assertIn(rec["id"], [x["id"] for x in d["recipes"]])
        self.assertEqual([x["text"] for x in d["logs"] if x["id"] == log["id"]], ["重启前写的"])


if __name__ == "__main__":
    unittest.main()
