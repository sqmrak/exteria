"""a stand-in for the app side of _exteria.service, used by the plugin tests: it answers the services and records the ui operations"""

import json
import os
import sys
import types

fake = types.ModuleType("_exteria")
fake.calls = []
fake.ops = []
fake.settings = {}
fake.menu = []
fake.timers = []
fake.picks = []
fake.time_picks = []
fake.story_presses = 0
fake.story_forgotten = []
fake.sheets = []
fake.current = {"kind": "chat", "dialog": 777, "user": {"id": 777, "first_name": "Ann"}}
fake.plugins_dir = "/tmp"
fake.cache_dir = "/tmp"
fake.language = "en"
fake.layer = 200
fake.proxies = {"exclude_simple": False, "exceptions": []}
fake.picks_root = "/var/pictures"
fake.image_picks = []
fake.bitmaps = {}
fake.pictures = {}
fake.encoded = []
fake.cards = []
fake.me = 4242
fake.saved = {"messages": [], "music": [], "next_id": 100, "calls": [], "errors": {}, "inbox": []}


class Music:
    """a stand-in for the music player of the app and its plugin services (exteria_plugin_music.m), with the same rules: a song that starts is a new
    playback, a player that was taken out keeps its number and plays on until it is released, a volume set to a player that is gone is refused"""

    def __init__(self):
        self.queue = []
        self.reset()

    def reset(self, queue=None):
        self.queue = list(queue if queue is not None else [])
        self.index = 0
        self.playback = 0
        self.state = "idle"
        self.alive = False
        self.position_ms = 0
        self.duration_ms = 0
        self.speed = 1.0
        self.shuffle = False
        self.repeat = 0
        self.volume = 1.0
        self.ghosts = {}
        self.volumes = []
        self.log = []

    def entry(self, index):
        song = dict(self.queue[index])
        song["index"] = index
        return song

    def start(self, index):
        """the music player starts the song at index, as startCurrent does"""
        self.index = index
        self.playback += 1
        self.state = "playing"
        self.alive = True
        self.volume = 1.0
        self.position_ms = 0
        self.duration_ms = int(self.queue[index].get("duration", 0)) * 1000
        self.log.append(("start", index))

    def app_starts(self, index):
        """a tap in the app: the plugins are asked first, as the music player asks them"""
        import exteria_host
        self.index = index
        if exteria_host.music_play(index):
            return
        self.start(index)

    def app_pauses(self):
        import exteria_host
        if self.state != "playing":
            return
        if exteria_host.music_pause():
            return
        self.state = "paused"
        self.log.append(("pause", None))

    def player(self, data):
        playback = int(data["id"])
        current = playback and playback == self.playback and self.alive
        ghost = self.ghosts.get(playback)
        if not current and ghost is None:
            raise RuntimeError("PLAYER_GONE")
        op = data["op"]
        if op == "state":
            if current:
                return {"playing": self.state == "playing", "position_ms": self.position_ms, "duration_ms": self.duration_ms, "speed": self.speed}
            return {"playing": True, "position_ms": ghost["position_ms"], "duration_ms": ghost["duration_ms"], "speed": self.speed}
        if op == "volume":
            self.volumes.append((playback, data["value"]))
            if current:
                self.volume = data["value"]
            else:
                ghost["volume"] = data["value"]
            return {}
        if op == "release":
            if current:
                raise RuntimeError("the song that plays is let go through cleanupPlayer")
            del self.ghosts[playback]
            self.log.append(("release", playback))
            return {}
        raise RuntimeError("not an operation of a player: %s" % op)

    def service(self, name, data):
        count = len(self.queue)
        if name == "music.state":
            state = {"id": self.playback, "state": self.state, "position_ms": self.position_ms, "duration_ms": self.duration_ms, "speed": self.speed,
                     "shuffle": self.shuffle, "repeat": self.repeat, "count": count}
            if count:
                state["position"] = self.index
                if self.state != "idle":
                    state["track"] = self.entry(self.index)
            return state
        if name == "music.entry":
            index = data["index"] if "index" in data else data["position"]
            if not 0 <= index < count:
                raise RuntimeError("the queue has no such song")
            return self.entry(index)
        if name == "music.peek":
            at = self.index + 1
            if at >= count:
                at = 0 if self.repeat == 1 and count else None
            return {} if at is None else {"entry": self.entry(at)}
        if name == "music.start":
            if not 0 <= data["index"] < count:
                raise RuntimeError("the queue has no such song")
            self.start(data["index"])
            return {"id": self.playback}
        if name == "music.pause":
            was = self.state == "playing"
            if was:
                self.state = "paused"
                self.log.append(("pause", None))
            return {"paused": was}
        if name == "music.cleanup":
            self.alive = False
            return {}
        if name == "music.detach":
            if not self.alive:
                return {"detached": False}
            self.ghosts[self.playback] = {"volume": self.volume, "position_ms": self.position_ms, "duration_ms": self.duration_ms}
            self.alive = False
            self.log.append(("detach", self.playback))
            return {"detached": True}
        if name == "music.player":
            return self.player(data)
        raise RuntimeError("%s is not served" % name)


fake.music = Music()

_handles = [0]


def _new_handle():
    _handles[0] += 1
    return _handles[0]


def _account(name, data):
    """a stand-in for Saved Messages and the saved music of the profile. the answer waits in the inbox until a test delivers it on its own thread,
    which is the main thread of the app in the real thing"""
    state = fake.saved
    op = name[len("account."):]
    state["calls"].append((op, data))
    error = state["errors"].get(op)
    answer = {}
    if error is None:
        if op == "history":
            newest = sorted(state["messages"], key=lambda m: -m["id"])[:data["limit"]]
            answer = {"messages": [dict(m) for m in newest]}
        elif op == "saved_music":
            answer = {"documents": state["music"][data["offset"]:data["offset"] + 30], "count": len(state["music"])}
        elif op == "save_music":
            doc = data["doc"]
            state["music"] = [d for d in state["music"] if d["id"] != doc["id"]]
            if not data["unsave"]:
                known = [m["doc"] for m in state["messages"] if m.get("doc") and m["doc"]["id"] == doc["id"]]
                state["music"].insert(0, known[0] if known else dict(doc, name="", mime="", title="", performer="", duration=0, size=0, thumb=False))
        elif op == "delete":
            state["messages"] = [m for m in state["messages"] if m["id"] not in data["ids"]]
        elif op == "story_post":
            state.setdefault("stories", []).append(dict(data))
        elif op == "send_audio":
            state["next_id"] += 1
            doc = {"id": state["next_id"] * 7, "access_hash": 99, "dc": 2, "file_ref": "0a0b", "size": os.path.getsize(data["path"]), "name": os.path.basename(data["path"]),
                   "mime": data["mime"], "title": data["title"], "performer": data["performer"], "duration": data["duration_ms"] // 1000, "thumb": True}
            state["messages"].append({"id": state["next_id"], "text": data["caption"], "date": 1, "doc": doc})
            answer = {"id": state["next_id"]}

    state["inbox"].append((data["token"], error, answer))


def deliver():
    """the answers of the app that are waiting, to python; the ones that ask for more in turn are delivered too. True when there was any"""
    import exteria_host
    delivered = False
    while fake.saved["inbox"]:
        token, error, answer = fake.saved["inbox"].pop(0)
        exteria_host.account_result(token, error, answer)
        delivered = True
    return delivered


fake.deliver = deliver


def service(name, payload):
    data = json.loads(payload) if payload else {}
    fake.calls.append((name, data))
    if name == "settings.get":
        return json.dumps({"value": fake.settings.get((data["plugin"], data["key"]))})
    if name == "settings.set":
        fake.settings[(data["plugin"], data["key"])] = data["value"]
        return "{}"
    if name == "settings.replace":
        for key in [key for key in fake.settings if key[0] == data["plugin"]]:
            del fake.settings[key]
        for key, value in json.loads(data["value"]).items():
            fake.settings[(data["plugin"], key)] = json.dumps(value)
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
    if name == "app.pick_time":
        fake.time_picks.append(data)
        return "{}"
    if name == "story.publish":
        fake.story_presses += 1
        return "{}"
    if name == "story.forget":
        fake.story_forgotten.append(data["token"])
        return "{}"
    if name.startswith("account."):
        _account(name, data)
        return "{}"
    if name.startswith("music."):
        return json.dumps(fake.music.service(name, data))
    if name == "app.pick_root":
        return json.dumps({"value": fake.picks_root})
    if name == "app.pick_image":
        fake.image_picks.append(data)
        return "{}"
    if name == "bitmap.decode":
        size = fake.pictures.get(data["path"])
        if size is None:
            raise RuntimeError("bitmap.decode: not a picture")
        scale = min(1.0, data["side"] / max(size))
        handle = _new_handle()
        fake.bitmaps[handle] = {"w": max(1, round(size[0] * scale)), "h": max(1, round(size[1] * scale)), "blur": 0}
        return json.dumps(dict(fake.bitmaps[handle], handle=handle))
    if name in ("bitmap.scale", "bitmap.copy"):
        source = fake.bitmaps[data["handle"]]
        handle = _new_handle()
        fake.bitmaps[handle] = {"w": data.get("w", source["w"]), "h": data.get("h", source["h"]), "blur": source["blur"]}
        return json.dumps(dict(fake.bitmaps[handle], handle=handle))
    if name == "bitmap.crop":
        source = fake.bitmaps[data["handle"]]
        if data["x"] < 0 or data["y"] < 0 or data["x"] + data["w"] > source["w"] or data["y"] + data["h"] > source["h"]:
            raise ValueError("bitmap.crop: the rectangle is not inside the picture")
        handle = _new_handle()
        fake.bitmaps[handle] = {"w": data["w"], "h": data["h"], "blur": source["blur"]}
        return json.dumps(dict(fake.bitmaps[handle], handle=handle))
    if name == "bitmap.encode":
        fake.encoded.append(data)
        with open(data["path"], "wb") as handle:
            handle.write(b"\xff\xd8" + b"j" * 900)
        return "{}"
    if name == "bitmap.blur":
        fake.bitmaps[data["handle"]]["blur"] = data["radius"]
        return "{}"
    if name == "bitmap.release":
        for handle in data["handles"]:
            fake.bitmaps.pop(handle, None)
        return "{}"
    if name == "page.cards":
        fake.cards.append(data["alpha"])
        return "{}"
    if name == "app.current":
        return json.dumps(fake.current)
    if name == "app.me":
        return json.dumps({"id": fake.me, "first_name": "Me"})
    if name == "app.language":
        return json.dumps({"value": fake.language})
    if name == "app.version":
        return json.dumps({"value": "1.0"})
    if name == "net.proxies":
        return json.dumps(fake.proxies)
    if name == "app.protocol":
        return json.dumps({"layer": fake.layer})
    if name == "app.muted":
        return json.dumps({"value": False})
    if name == "theme.color":
        return json.dumps({"value": 0xFF112233})
    if name == "theme.dark":
        return json.dumps({"value": False})
    return "{}"


fake.service = service
sys.modules["_exteria"] = fake
