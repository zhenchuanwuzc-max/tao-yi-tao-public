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

    def test_new_question_date_uses_local_timezone(self):
        self.assertIn("function localDateISO(date)", HTML)
        self.assertIn("trueQuestionDraft={raisedAt:localDateISO()}", HTML)
        self.assertNotIn(
            'trueQuestionDraft={raisedAt:new Date().toISOString().slice(0,10)}',
            HTML,
        )

    def test_industry_editor_contract_remains(self):
        self.assertIn('id:"fw_industry"', HTML)
        self.assertIn("function renderFwEditor()", HTML)
        self.assertIn('data-fwopen', HTML)


if __name__ == "__main__":
    unittest.main()
