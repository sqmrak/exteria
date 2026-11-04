"""a stand-in for the app side of _exteria.service, used by the plugin tests: it answers the services and records the ui operations"""

import json
import sys
import types

fake = types.ModuleType("_exteria")
fake.calls = []
fake.ops = []
fake.settings = {}
fake.menu = []
fake.timers = []
fake.picks = []
fake.sheets = []
fake.current = {"kind": "chat", "dialog": 777, "user": {"id": 777, "first_name": "Ann"}}
fake.plugins_dir = "/tmp"
fake.cache_dir = "/tmp"
fake.language = "en"


def service(name, payload):
    data = json.loads(payload) if payload else {}
    fake.calls.append((name, data))
    if name == "settings.get":
        return json.dumps({"value": fake.settings.get((data["plugin"], data["key"]))})
    if name == "settings.set":
        fake.settings[(data["plugin"], data["key"])] = data["value"]
        return "{}"
    if name == "settings.export":
        return json.dumps({"value": json.dumps({k[1]: json.loads(v) for k, v in fake.settings.items() if k[0] == data["plugin"]})})
    if name == "menu.add":
        fake.menu.append(data["item"])
        return json.dumps({"value": "item%d" % len(fake.menu)})
    if name in ("permission.has", "permission.check"):
        return json.dumps({"value": True})
    if name == "permission.unsafe":
        return json.dumps({"value": False})
    if name == "plugins.dir":
        return json.dumps({"value": fake.plugins_dir})
    if name == "files.cache":
        return json.dumps({"value": fake.cache_dir})
    if name == "audio.open":
        return json.dumps({"duration_ms": 1234})
    if name == "ui.apply":
        fake.ops.extend(data["ops"])
        return "{}"
    if name == "ui.screen":
        return json.dumps({"w": 320, "h": 480, "top": 20, "bottom": 0})
    if name == "ui.measure":
        return json.dumps({"w": min(int(len(data["text"]) * data["size"] * 0.6), data["width"]),
                           "h": int(data["size"] * 1.3)})
    if name == "ui.run":
        fake.timers.append((data["token"], data["delay"]))
        return "{}"
    if name == "sheet.open":
        fake.sheets.append(data)
        return json.dumps({"id": len(fake.sheets)})
    if name == "sensor.available":
        return json.dumps({"value": True})
    if name == "app.pick":
        fake.picks.append(data)
        return "{}"
    if name == "app.current":
        return json.dumps(fake.current)
    if name == "app.me":
        return json.dumps({"id": 1, "first_name": "Me"})
    if name == "app.language":
        return json.dumps({"value": fake.language})
    if name == "app.version":
        return json.dumps({"value": "1.0"})
    if name == "app.muted":
        return json.dumps({"value": False})
    if name == "theme.color":
        return json.dumps({"value": 0xFF112233})
    if name == "theme.dark":
        return json.dumps({"value": False})
    return "{}"


fake.service = service
sys.modules["_exteria"] = fake
