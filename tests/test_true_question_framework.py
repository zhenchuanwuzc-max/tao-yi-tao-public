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
        data_file = Path.home() / "tao-yi-tao-data" / "data.json"
        if not data_file.exists():
            self.skipTest("本机没有数据仓，跳过真实数据检查")
        import json
        frameworks = json.loads(data_file.read_text(encoding="utf-8")).get("frameworks", [])
        self.assertTrue(any(f.get("fwId") == "fw_industry" for f in frameworks),
                        "旧的行业判断记录应仍然存在")


if __name__ == "__main__":
    unittest.main()
