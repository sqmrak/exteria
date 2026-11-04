import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

fake = fakeapp.fake
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

import exteria_host  # noqa: E402
from ui.alert import AlertDialogBuilder  # noqa: E402
from ui.bulletin import BulletinHelper  # noqa: E402


class Dialogs(unittest.TestCase):
    def setUp(self):
        del fake.calls[:]
        del fake.timers[:]

    def calls(self, name):
        return [d for n, d in fake.calls if n == name]

    def run_timers(self):
        while fake.timers:
            token, _ = fake.timers.pop(0)
            exteria_host.run_token(token)

    def test_buttons_reach_the_app_in_ios_order_and_answers_come_back(self):
        answers = []
        builder = AlertDialogBuilder()
        builder.set_title("Delete?").set_message("It cannot be undone")
        builder.set_positive_button("Delete", lambda b, which: answers.append(("positive", which)))
        builder.set_negative_button("Cancel", lambda b, which: answers.append(("negative", which)))
        builder.show()
        self.run_timers()
        shown = self.calls("ui.alert")[0]
        self.assertEqual((shown["title"], shown["message"]), ("Delete?", "It cannot be undone"))
        self.assertEqual(shown["buttons"], ["Cancel", "Delete"])
        self.assertEqual(shown["cancel"], 0)
        exteria_host.alert_result(shown["token"], 1)
        self.assertEqual(answers, [("positive", -1)])

    def test_the_cancel_button_answers_negative(self):
        answers = []
        builder = AlertDialogBuilder()
        builder.set_message("x").set_positive_button("OK", lambda b, w: answers.append(w))
        builder.set_negative_button("No", lambda b, w: answers.append(w))
        builder.show()
        self.run_timers()
        exteria_host.alert_result(self.calls("ui.alert")[0]["token"], 0)
        self.assertEqual(answers, [-2])

    def test_a_list_of_items_is_a_choice(self):
        picked = []
        builder = AlertDialogBuilder()
        builder.set_title("Pick").set_items(["a", "b", "c"], lambda b, which: picked.append(which))
        builder.show()
        self.run_timers()
        asked = self.calls("ui.choose")[0]
        self.assertEqual(asked["items"], ["a", "b", "c"])
        exteria_host.alert_result(asked["token"], 2)
        self.assertEqual(picked, [2])

    def test_a_progress_dialog_says_it_is_missing(self):
        with self.assertRaises(NotImplementedError):
            AlertDialogBuilder(alert_type=AlertDialogBuilder.ALERT_TYPE_LOADING)

    def test_bulletins_become_banners(self):
        BulletinHelper.show_info("Saved")
        BulletinHelper.show_error("Broke")
        self.run_timers()
        self.assertEqual([c["text"] for c in self.calls("ui.toast")], ["Saved", "Broke"])


if __name__ == "__main__":
    unittest.main()
