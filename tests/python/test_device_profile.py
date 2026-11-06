"""the device profile a plugin sends with invokeWithLayer(initConnection(help.getNearestDc)): the record is serialized, read back, checked field by field,
and only the three device texts reach the app. the app is the stand-in of fakeapp.py; the real device_fingerprint_spoofer runs over it when
EXTERIA_DEVICE_SPOOFER names its file"""

import os
import shutil
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

fake = fakeapp.fake
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

import exteria_host  # noqa: E402
from android.os import Build  # noqa: E402
from extera_utils import plugin_loader  # noqa: E402
from java.lang import Class  # noqa: E402
from org.telegram.tgnet import SerializedData, TLObject, TLRPC, requests  # noqa: E402

PLUGINS = None
_saved = {}


def setUpModule():
    global PLUGINS
    PLUGINS = tempfile.mkdtemp(prefix="exteria-device-")
    _saved["dir"] = fake.plugins_dir
    _saved["cached"] = plugin_loader._plugins_dir_cached
    fake.plugins_dir = PLUGINS
    plugin_loader._plugins_dir_cached = None
    exteria_host._elyx_libraries()


def tearDownModule():
    fake.plugins_dir = _saved["dir"]
    plugin_loader._plugins_dir_cached = _saved["cached"]
    shutil.rmtree(PLUGINS, ignore_errors=True)


def wire(layer=None, model="Pixel 8", system="SDK 35", app="12.1.1", flags=0, query=None, tail=b"", constructor=0xC1CD5EA9, outer=0xDA9B0D0D,
         strings=("en", "android", "en")):
    """the bytes of invokeWithLayer(initConnection(...)), written the way the android client writes them"""
    data = SerializedData()
    data.writeInt32(outer)
    data.writeInt32(TLRPC.LAYER if layer is None else layer)
    data.writeInt32(constructor)
    data.writeInt32(flags)
    data.writeInt32(33010234)
    for text in (model, system, app) + tuple(strings):
        data.writeString(text)
    data.writeInt32(TLRPC.TL_help_getNearestDc.CONSTRUCTOR if query is None else query)
    return data.getBytes() + tail


class Carrier(TLObject):
    """a record that writes the bytes it was given, as a plugin's own serializeToStream does"""

    def __init__(self, data):
        self._data = data

    def serializeToStream(self, stream):
        stream._bytes += self._data


def planned(data):
    return requests._device_profile(Carrier(data))


class Serialization(unittest.TestCase):
    def test_strings_are_padded_to_four_bytes_and_long_ones_carry_three_length_bytes(self):
        stream = SerializedData()
        stream.writeString("abc")
        stream.writeString("abcd")
        stream.writeString("x" * 300)
        stream.writeInt32(0xDA9B0D0D)
        stream.writeInt64(-2)
        data = stream.getBytes()
        self.assertEqual(data[:4], b"\x03abc")
        self.assertEqual(data[4:12], b"\x04abcd\0\0\0")
        self.assertEqual(data[12:16], b"\xfe\x2c\x01\x00")
        self.assertEqual(len(data), 4 + 8 + 4 + 300 + 0 + 4 + 8)
        self.assertEqual(struct.unpack("<I", data[-12:-8])[0], 0xDA9B0D0D)
        self.assertEqual(struct.unpack("<q", data[-8:])[0], -2)

    def test_class_for_name_gives_the_shim_or_says_it_is_missing(self):
        from java import ClassNotFoundException
        self.assertEqual(Class.forName("org.telegram.tgnet.TLObject").getName(), "org.telegram.tgnet.TLObject")
        with self.assertRaises(ClassNotFoundException):
            Class.forName("org.telegram.ui.ChatUsersActivity")


class DeviceProfile(unittest.TestCase):
    def test_the_three_texts_are_taken_and_the_rest_of_the_wire_is_the_apps_own(self):
        operation, payload, parse = planned(wire(model="samsungSM-S928B", system="SDK 34", app="12.1.1", strings=("ru", "tdesktop", "xx")))
        self.assertEqual(operation, "device_profile")
        self.assertEqual(payload, {"model": "samsungSM-S928B", "system": "SDK 34", "app": "12.1.1"})
        self.assertIsInstance(parse({}), TLRPC.TL_boolTrue)

    def test_an_empty_app_version_goes_through_and_text_keeps_its_characters(self):
        _, payload, _ = planned(wire(model="Телефон 🙂", system="SDK 1", app=""))
        self.assertEqual(payload, {"model": "Телефон 🙂", "system": "SDK 1", "app": ""})

    def test_the_real_profile_of_the_stand_in_asks_for_the_way_back(self):
        _, payload, _ = planned(wire(model=str(Build.MANUFACTURER) + str(Build.MODEL), system="SDK 33", app="whatever"))
        self.assertEqual(payload, {"restore": True})

    def test_an_empty_model_or_system_version_is_refused(self):
        with self.assertRaises(ValueError):
            planned(wire(model=""))
        with self.assertRaises(ValueError):
            planned(wire(system=""))

    def test_anything_but_the_one_wire_shape_is_refused_by_name(self):
        for data, part in (
            (wire(outer=0x1234), "invokeWithLayer"),
            (wire(constructor=0x1234), "initConnection"),
            (wire(flags=1), "proxy"),
            (wire(query=0x1234), "getNearestDc"),
            (wire(tail=b"\0\0\0\0"), "more fields"),
            (wire()[:-8], "ends before"),
            (wire(layer=TLRPC.LAYER + 1), "layer"),
            (b"", "ends before"),
        ):
            with self.subTest(part=part), self.assertRaises(NotImplementedError) as caught:
                planned(data)
            self.assertIn(part, str(caught.exception))

    def test_send_hands_the_profile_to_the_app_and_gives_the_answer_back(self):
        answers = []
        fake.saved["calls"].clear()
        token = requests.send(Carrier(wire()), lambda response, error: answers.append((response, error)))
        self.assertEqual(fake.saved["calls"], [("device_profile", {"token": token, "model": "Pixel 8", "system": "SDK 35", "app": "12.1.1"})])
        requests.account_result(token, None, {})
        self.assertIsInstance(answers[0][0], TLRPC.TL_boolTrue)
        self.assertIsNone(answers[0][1])
        answers.clear()
        token = requests.send(Carrier(wire()), lambda response, error: answers.append((response, error)))
        requests.account_result(token, "DEVICE_INVALID", {})
        self.assertIsNone(answers[0][0])
        self.assertEqual((answers[0][1].code, answers[0][1].text), (400, "DEVICE_INVALID"))

    def test_a_request_that_is_no_profile_is_still_refused_by_name(self):
        with self.assertRaises(NotImplementedError) as caught:
            requests.send(object(), lambda *_: None)
        self.assertIn("cannot be sent from a plugin on ios", str(caught.exception))


@unittest.skipUnless(os.environ.get("EXTERIA_DEVICE_SPOOFER"), "set EXTERIA_DEVICE_SPOOFER to the file of the plugin")
class RealPlugin(unittest.TestCase):
    def setUp(self):
        self.path = os.path.join(PLUGINS, "device_fingerprint_spoofer.plugin")
        shutil.copy(os.environ["EXTERIA_DEVICE_SPOOFER"], self.path)
        self.assertTrue(exteria_host.load(self.path, "device_fingerprint_spoofer")["ok"])
        self.plugin = plugin_loader.plugins["device_fingerprint_spoofer"].instance
        # the settings of the plugin outlive its unload, so a test starts from the defaults
        for key, value in (("enabled", True), ("profile", 1), ("spoof_app", True)):
            self.plugin.set_setting(key, value)
        fake.saved["calls"].clear()

    def tearDown(self):
        exteria_host.unload("device_fingerprint_spoofer")

    def status_rows(self):
        return [row.get("text") for row in exteria_host.settings("device_fingerprint_spoofer") if row.get("text")]

    def test_the_account_is_active_and_the_profile_reaches_the_app_when_applied(self):
        self.plugin.apply_runtime(force_new=True, notify=False, force=True)
        self.assertEqual([(op, {k: v for k, v in data.items() if k != "token"}) for op, data in fake.saved["calls"]],
                         [("device_profile", {"model": "samsungSM-S928B", "system": "SDK 34", "app": "12.1.1"})])
        requests.account_result(fake.saved["calls"][0][1]["token"], None, {})
        self.assertTrue(any("принято сервером" in text and "samsungSM-S928B" in text for text in self.status_rows()))

    def test_the_server_refusal_is_shown_in_the_status(self):
        self.plugin.apply_runtime(force_new=True, notify=False, force=True)
        requests.account_result(fake.saved["calls"][0][1]["token"], "DEVICE_INVALID", {})
        self.assertTrue(any("ошибка сервера: DEVICE_INVALID" in text for text in self.status_rows()))

    def test_switching_the_spoof_off_asks_the_app_for_the_real_device(self):
        self.plugin.set_setting("enabled", False)
        self.plugin.apply_runtime(force_new=True, notify=False, force=True)
        self.assertEqual([data.get("restore") for _, data in fake.saved["calls"]], [True])

    def test_the_hooks_of_the_android_client_that_ios_has_no_class_for_say_so(self):
        rows = self.status_rows()
        self.assertTrue(any(text.startswith("хуки старта не установлены: ClassNotFoundException") and "ConnectionsManager" in text for text in rows))
        self.assertTrue(any("RecyclerListView" in text for text in rows))

    def test_without_a_signed_in_person_nothing_is_sent(self):
        saved, fake.me = fake.me, 0
        try:
            self.plugin.apply_runtime(force_new=True, notify=False, force=True)
        finally:
            fake.me = saved
        self.assertEqual(fake.saved["calls"], [])
        self.assertTrue(any("нет активных аккаунтов" in text for text in self.status_rows()))


if __name__ == "__main__":
    unittest.main()
