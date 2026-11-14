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
fake.opened = []
fake.clipboard = []
fake.notices = []
fake.notices_cancelled = []
fake.notices_on = True
fake.plugin_pages = {"shown"}
fake.settings_opened = []
fake.progress = {}
fake.progress_log = []
fake.chat = {"messages": [], "log": [], "channel": False, "errors": {}}
fake.tabs = {}
fake.tabs_up = True
fake.peers = set()
fake.played = []
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
        if name == "music.play_docs":
            # the app starts the first song of the queue it was handed; the documents are what python names them by
            if not data["docs"] or not 0 <= data["index"] < len(data["docs"]):
                raise RuntimeError("a queue of songs and the place to start are needed")
            fake.played.append(dict(data))
            self.playback += 1
            self.state = "playing"
            self.alive = True
            return {"id": self.playback}
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
        elif op == "chat_music":
            songs = sorted(state.get("chat_music", {}).get(data["dialog"], []), key=lambda m: m["id"])
            if data["dialog"] not in fake.peers and data["dialog"] != fake.me:
                error = "PEER_ID_INVALID"
            else:
                answer = {"messages": songs[:1] if data["first"] else songs[-1:]}
        elif op == "saved_music" and "user" in data:
            songs = state.get("profile_music", {}).get(data["user"])
            if songs is None or (data["user"] not in fake.peers and data["user"] != fake.me):
                error = "USER_ID_INVALID"
            else:
                answer = {"documents": songs[data["offset"]:data["offset"] + 30], "count": len(songs)}
        elif op == "saved_music":
            answer = {"documents": state["music"][data["offset"]:data["offset"] + 30], "count": len(state["music"])}
        elif op == "save_music":
            doc = data["doc"]
            state["music"] = [d for d in state["music"] if d["id"] != doc["id"]]
            if not data["unsave"]:
                known = [m["doc"] for m in state["messages"] if m.get("doc") and m["doc"]["id"] == doc["id"]]
                state["music"].insert(0, known[0] if known else dict(doc, name="", mime="", title="", performer="", duration=0, size=0, thumb=False))
        elif op == "chat_page":
            chat = fake.chat
            chat["log"].append(("page", dict(data)))
            if "page" in chat["errors"]:
                error = chat["errors"]["page"]
            else:
                rows = [dict(m) for m in sorted(chat["messages"], key=lambda m: -m["id"]) if not data["offset_id"] or m["id"] < data["offset_id"]]
                if data["mode"] == "mine":
                    rows = [m for m in rows if m["out"]]
                answer = {"messages": rows[:data["limit"]]}
        elif op == "delete":
            chat = fake.chat
            chat["log"].append(("delete", dict(data)))
            if "delete" in chat["errors"]:
                error = chat["errors"]["delete"]
            else:
                state["messages"] = [m for m in state["messages"] if m["id"] not in data["ids"]]
                chat["messages"] = [m for m in chat["messages"] if m["id"] not in data["ids"]]
                answer = {"count": len(data["ids"])}
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
    if name == "ui.text_image":
        # a stand-in for the glyph picture of the app: one solid block of 0.6 em per character, in a box of the size ui.measure gives.
        # it has the shape of the real answer (an 8 bit coverage mask with the baseline row), not the look of a font
        import base64
        size = data["size"]
        w, h = int(len(data["text"]) * size * 0.6) + 2, int(size * 1.3) + 2
        ascent = int(size * 0.8) + 1
        rows = bytearray(w * h)
        for y in range(1, 1 + int(size * 1.0)):
            for x in range(1, w - 1):
                rows[y * w + x] = 255
        return json.dumps({"w": w, "h": h, "ascent": ascent, "descent": int(size * 0.2), "alpha": base64.b64encode(bytes(rows)).decode()})
    if name == "app.open_url":
        from urllib.parse import urlsplit
        parts = urlsplit(data["url"])
        if parts.scheme not in ("http", "https", "tg") or (parts.scheme != "tg" and not parts.netloc):
            raise RuntimeError("only http, https and tg addresses open")
        fake.opened.append(data["url"])
        return "{}"
    if name == "app.plugin_settings":
        if data.get("plugin") not in fake.plugin_pages:
            raise RuntimeError("no such plugin")
        fake.settings_opened.append(data["plugin"])
        return "{}"
    if name == "app.notice":
        if not fake.notices_on:
            raise RuntimeError("the notifications are switched off in the app")
        fake.notices.append((data["key"], data["title"], data["text"]))
        return "{}"
    if name == "app.notice_cancel":
        fake.notices_cancelled.append(data["key"])
        return "{}"
    if name == "app.notices_enabled":
        return json.dumps({"value": fake.notices_on})
    if name == "app.clipboard_set":
        if not isinstance(data.get("text"), str) or len(data["text"].encode()) > 1024 * 1024:
            raise RuntimeError("no text, or more than 1 MiB of it")
        fake.clipboard.append(data["text"])
        return "{}"
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
    if name.startswith("progress."):
        fake.progress_log.append((name, data))
        if name == "progress.show":
            fake.progress[data["token"]] = dict(data)
        elif name == "progress.update":
            fake.progress[data["token"]].update(data)
        elif name == "progress.close":
            fake.progress.pop(data["token"], None)
        return "{}"
    if name == "tabs.state":
        return json.dumps({"value": fake.tabs_up})
    if name == "tabs.set":
        if data.get("icon") not in (None, "music"):
            raise RuntimeError("the bar has no icon %s" % data["icon"])
        fake.tabs[data["slot"]] = dict(data)
        return "{}"
    if name == "peer.known":
        return json.dumps({"value": data["dialog"] == fake.me or data["dialog"] in fake.peers})
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
