import http.server
import json
import os
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

fake = fakeapp.fake
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

import exteria_host  # noqa: E402
import requests  # noqa: E402
from java.io import File  # noqa: E402
from org.telegram.messenger import ApplicationLoader, DispatchQueue, SendMessagesHelper  # noqa: E402

PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 40


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        if self.path.startswith("/png"):
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(PNG)))
            self.end_headers()
            self.wfile.write(PNG)
        elif self.path.startswith("/redirect"):
            self.send_response(302)
            self.send_header("Location", "/png?x=1")
            self.end_headers()
        elif self.path.startswith("/echo"):
            body = json.dumps({"path": self.path}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()

    def do_POST(self):
        size = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(size)
        reply = json.dumps({"type": self.headers.get("Content-Type"), "body": body.decode()}).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)


class Requests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.base = "http://127.0.0.1:%d" % cls.server.server_address[1]
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def test_streams_a_body_with_headers(self):
        response = requests.get(self.base + "/png", params={"a": "b c"}, stream=True, timeout=5)
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.headers.get("content-type").startswith("image/"))
        self.assertEqual(b"".join(response.iter_content(chunk_size=7)), PNG)

    def test_follows_a_redirect_and_builds_the_query(self):
        self.assertEqual(requests.get(self.base + "/redirect", timeout=5).content, PNG)
        self.assertEqual(requests.get(self.base + "/echo", params={"q": "a b", "n": 1}, timeout=5).json(), {"path": "/echo?q=a+b&n=1"})

    def test_does_not_follow_when_told(self):
        self.assertEqual(requests.get(self.base + "/redirect", allow_redirects=False, timeout=5).status_code, 302)

    def test_posts_json_and_forms(self):
        self.assertEqual(requests.post(self.base + "/x", json={"k": 1}, timeout=5).json(), {"type": "application/json", "body": '{"k": 1}'})
        reply = requests.post(self.base + "/x", data={"k": "v w"}, timeout=5).json()
        self.assertEqual((reply["type"], reply["body"]), ("application/x-www-form-urlencoded", "k=v+w"))

    def test_http_errors(self):
        response = requests.get(self.base + "/missing", timeout=5)
        self.assertEqual(response.status_code, 404)
        with self.assertRaises(requests.HTTPError):
            response.raise_for_status()

    def test_a_refused_connection_is_a_requests_error(self):
        with self.assertRaises(requests.ConnectionError):
            requests.get("http://127.0.0.1:1/", timeout=2)

    def test_refuses_an_option_it_does_not_know(self):
        with self.assertRaises(TypeError):
            requests.get(self.base + "/png", verify=False)


class Files(unittest.TestCase):
    def test_file_behaves_like_java_io_file(self):
        with tempfile.TemporaryDirectory() as root:
            folder = File(root, "images")
            self.assertFalse(folder.exists())
            self.assertTrue(folder.mkdirs())
            self.assertFalse(folder.mkdirs())
            self.assertTrue(folder.isDirectory())
            item = File(folder, "qr_1.png")
            with open(item.getAbsolutePath(), "wb") as out:
                out.write(PNG)
            self.assertEqual([f.getName() for f in folder.listFiles()], ["qr_1.png"])
            self.assertEqual(item.length(), len(PNG))
            self.assertGreater(item.lastModified(), 0)
            self.assertTrue(item.delete())
            self.assertFalse(item.delete())
            self.assertIsNone(File(root, "none").listFiles())

    def test_files_dir_is_the_cache_folder_of_the_app(self):
        with tempfile.TemporaryDirectory() as root:
            fake.cache_dir = root
            try:
                self.assertEqual(ApplicationLoader.getFilesDirFixed().getAbsolutePath(), os.path.abspath(root))
            finally:
                fake.cache_dir = "/tmp"


class Queues(unittest.TestCase):
    def setUp(self):
        fake.calls.clear()
        fake.timers.clear()

    def pump(self, until, seconds=5):
        """what the app does on its main thread: run the tokens a worker queued"""
        end = time.monotonic() + seconds
        while time.monotonic() < end and not until():
            while fake.timers:
                token, _delay = fake.timers.pop(0)
                exteria_host.run_token(token)
            time.sleep(0.005)
        return until()

    def test_runs_in_order_with_a_delay_off_the_main_thread(self):
        queue = DispatchQueue("t")
        seen = []
        queue.postRunnable(lambda: seen.append(("late", threading.current_thread() is threading.main_thread())), 60)
        queue.postRunnable(lambda: seen.append(("first", threading.current_thread() is threading.main_thread())))
        self.assertTrue(self.pump(lambda: len(seen) == 2))
        self.assertEqual(seen, [("first", False), ("late", False)])

    def test_a_failing_runnable_does_not_stop_the_queue(self):
        queue = DispatchQueue("t2")
        seen = []
        queue.postRunnable(lambda: 1 / 0)
        queue.postRunnable(lambda: seen.append(1))
        self.assertTrue(self.pump(lambda: seen))

    def test_a_worker_call_into_the_app_runs_on_the_main_thread_and_returns(self):
        from android import _ui
        queue = DispatchQueue("t3")
        answers = []
        queue.postRunnable(lambda: answers.append(_ui.ask("theme.dark")))
        self.assertTrue(self.pump(lambda: answers))
        self.assertEqual(answers, [{"value": False}])
        self.assertIn("theme.dark", [name for name, _ in fake.calls])

    def test_sending_a_photo_asks_the_app_for_the_file(self):
        helper = SendMessagesHelper.getInstance()
        with tempfile.NamedTemporaryFile(suffix=".png") as photo:
            photo.write(PNG)
            photo.flush()
            self.assertIsNone(helper.generatePhotoSizes("/no/such/file.png", None))
            sizes = helper.generatePhotoSizes(photo.name, None)
            self.assertIsNotNone(sizes)
            params = SendMessagesHelper.SendMessageParams()
            params.peer = 777
            params.replyToMsg = None
            params.photo = sizes
            params.path = photo.name
            params.caption = "hi"
            helper.sendMessage(params)
        self.assertEqual(fake.calls[-1], ("chat.send_photo", {"peer": 777, "path": photo.name, "caption": "hi", "reply": 0}))


class MessageMenu(unittest.TestCase):
    def setUp(self):
        fake.calls.clear()
        fake.settings.clear()
        fake.timers.clear()
        fake.plugins_dir = os.path.join(ROOT, "tests", "python", "plugins")
        self.path = os.path.join(fake.plugins_dir, "voice.plugin")

    def tearDown(self):
        exteria_host.unload("voice")

    def test_a_message_item_gets_the_message_and_plays_a_sound_from_a_queue(self):
        with tempfile.TemporaryDirectory() as folder:
            fake.cache_dir = folder
            try:
                self.assertTrue(exteria_host.load(self.path, "voice")["ok"])
                menu = [item for name, item in fake.calls if name == "menu.add"]
                self.assertEqual((menu[0]["item"]["menu_type"], menu[0]["item"]["priority"]), ("MESSAGE_CONTEXT_MENU", 5))
                from app.exteraless import plugins as bridge
                item_id = next(key[1] for key in bridge._menu_callbacks if key[0] == "voice")
                exteria_host.menu_click("voice", item_id, {"message": {"id": 41, "text": "hello there", "out": False, "dialog": 777}})
                self.assertEqual(fake.settings[("voice", "text")], '"hello there"')
                self.assertEqual(fake.settings[("voice", "id")], "41")
                queue = Queues("test_runs_in_order_with_a_delay_off_the_main_thread")
                self.assertTrue(queue.pump(lambda: ("voice", "played") in fake.settings))
                names = [name for name, _ in fake.calls if name.startswith("audio.")]
                self.assertEqual(names, ["audio.open", "audio.start", "audio.stop", "audio.release"])
                self.assertEqual(fake.settings[("voice", "duration")], "1234")
                opened = next(data for name, data in fake.calls if name == "audio.open")
                self.assertEqual(opened["path"], folder + "/a.mp3")
            finally:
                fake.cache_dir = "/tmp"


if __name__ == "__main__":
    unittest.main()
