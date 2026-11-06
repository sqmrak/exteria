"""the music player of the android client over the music player of the app, for the plugins that mix one song into the next (zwyCrossfade).

a plugin of that kind reaches into MediaController: it hooks playMessage, cleanupPlayer and pauseMessage, reads its private fields
(audioPlayer, audioVolume and others) and drives the ExoPlayer of a song (VideoPlayer) by its volume. the music player of the app owns the
songs and the players, so everything here is a view of it (exteria_plugin_music.m answers the services "music.*"):

- audioPlayer is the playback that is current, a VideoPlayer with the number of the playback. setting it to None takes the player of the
  song out of the music player, which plays on until releasePlayer; that is how the plugin keeps the old song audible while the next one starts
- playMessage, cleanupPlayer and pauseMessage are the methods of the class the plugins hook. a song that starts or pauses in the app is
  announced to python first (exteria_host.music_play and music_pause), so a hook runs before the music player acts, as it does before the android one
- the playlist is presented in the order the android client has it: the next song is the one before the current in the list, so a plugin that
  walks the list as it does on android finds what the music player will play. SharedConfig.playOrderReversed is False for that reason

what has no counterpart is said by a value that matches it: audioVolumeAnimator and reporter are None (the app pauses without a volume
animation and has no listen report), audioFocus is the focus the app always has, and the delegate of a visualizer is kept and never called, since
the app draws no audio visualizer"""

from android import _ui
from java.lang import Object

# the focus that is not ducked; a phone call or another app pauses the player of the app, there is no state in between
AUDIO_FOCUS_GAIN = 2

# the playback states of the music player that have a song loaded
_LOADED = ("loading", "playing", "paused")


def _state():
    return _ui.ask("music.state")


def _message_of(entry):
    """the MessageObject of a song of the player. its id is the index in the queue, which playMessage starts"""
    from org.telegram.messenger import MessageObject
    from org.telegram.tgnet import TLRPC
    title = str(entry.get("title") or entry.get("name") or "")
    owner = TLRPC.Message(id=int(entry.get("index", 0)), message=title, out=False, attachPath=str(entry.get("path") or ""))
    message = MessageObject(owner, 0)
    message._track = dict(entry)
    return message


class _Playlist(Object):
    """the songs of the queue in the order of the android client, read from the app when asked"""

    def __init__(self, count):
        self._count = int(count)

    def size(self):
        return self._count

    def isEmpty(self):
        return self._count == 0

    def get(self, index):
        index = int(index)
        if not 0 <= index < self._count:
            raise IndexError("the playlist has %d songs, not a song %d" % (self._count, index))
        # the app counts in the order the songs are played; the android list counts the other way
        return _message_of(_ui.ask("music.entry", position=self._count - 1 - index))

    def __len__(self):
        return self._count

    def __iter__(self):
        return (self.get(index) for index in range(self._count))

    def toArray(self):
        return list(self)


class VideoPlayer(Object):
    """the player of one song: the playback that is current, or a player that was taken out of the music player. it reads its position and
    sets its volume in the app"""

    class AudioVisualizerDelegate(Object):
        """a plugin class implements onVisualizerUpdate(playing, animate, values) and needUpdate()"""

    allowMultipleInstances = False

    def __init__(self, playback_id):
        self._id = int(playback_id)
        self._visualizer = None

    def _player(self, op, **fields):
        return _ui.ask("music.player", id=self._id, op=op, **fields)

    def isPlaying(self):
        return bool(self._player("state")["playing"])

    def getDuration(self):
        return int(self._player("state")["duration_ms"])

    def getCurrentPosition(self):
        return int(self._player("state")["position_ms"])

    def getPlaybackSpeed(self):
        return float(self._player("state")["speed"])

    def setVolume(self, volume):
        self._player("volume", value=float(volume))

    def releasePlayer(self, _async=True):
        self._player("release")

    def setAudioVisualizerDelegate(self, delegate):
        self._visualizer = delegate

    def equals(self, other):
        return isinstance(other, VideoPlayer) and other._id == self._id

    def __eq__(self, other):
        return self.equals(other)

    def __hash__(self):
        return hash(self._id)


class MediaController(Object):
    _instance = None

    # the private fields of the android class that a plugin reads and writes
    audioFocus = AUDIO_FOCUS_GAIN
    audioVolume = 1.0
    audioVolumeAnimator = None
    reporter = None
    forceLoopCurrentPlaylist = False

    # the playback whose player was taken out; audioPlayer is None until the next song starts
    _detached = 0
    _players = {}

    @staticmethod
    def getInstance():
        if MediaController._instance is None:
            MediaController._instance = MediaController()
        return MediaController._instance

    @property
    def audioPlayer(self):
        state = _state()
        playback = int(state["id"])
        if not playback or state["state"] not in _LOADED or playback == self._detached:
            return None
        player = MediaController._players.get(playback)
        if player is None:
            MediaController._players.clear()
            player = MediaController._players[playback] = VideoPlayer(playback)
        return player

    @audioPlayer.setter
    def audioPlayer(self, value):
        if value is not None:
            raise NotImplementedError("the player of a song is the one of the app, it cannot be replaced by another")
        playback = int(_state()["id"])
        if _ui.ask("music.detach")["detached"]:
            self._detached = playback

    @property
    def shuffledPlaylist(self):
        return self.getPlaylist()

    def getPlaylist(self):
        return _Playlist(_state()["count"])

    def getPlayingMessageObject(self):
        state = _state()
        if state["state"] not in _LOADED or "track" not in state:
            return None
        return _message_of(state["track"])

    def getPlayingMessageObjectNum(self):
        state = _state()
        if "position" not in state or state["state"] not in _LOADED:
            return -1
        return int(state["count"]) - 1 - int(state["position"])

    def isMessagePaused(self):
        return _state()["state"] == "paused"

    def isPlayingMessage(self, message):
        state = _state()
        track = getattr(message, "_track", None)
        return bool(track and state["state"] == "playing" and "track" in state and state["track"]["key"] == track["key"])

    def playMessage(self, message):
        """starts the song of a message of the playlist. True when the music player took it"""
        track = getattr(message, "_track", None)
        if track is None or "index" not in track:
            raise NotImplementedError("only a song of the playlist of the app can be started from a plugin")
        self.cleanupPlayer(True, True, False, False)
        _ui.ask("music.start", index=int(track["index"]))
        return True

    def cleanupPlayer(self, notify=True, stop_service=True, by_voice_end=False, transfer_to_viewer=False):
        """lets the player of the current song go. a plugin that took the player out left nothing here to let go"""
        if self.audioPlayer is not None:
            _ui.ask("music.cleanup")

    def pauseMessage(self, message=None):
        """pauses the song that plays; True when there was one"""
        return bool(_ui.ask("music.pause")["paused"])

    def playNextMessage(self):
        """starts the song a tap on next starts"""
        found = _ui.ask("music.peek").get("entry")
        if found is None:
            return False
        return self.playMessage(_message_of(found))

    def _hooked(self):
        from de.robv.android.xposed import XposedBridge
        return any(target is MediaController for target, _name in list(XposedBridge._chains))


class _SharedConfigMeta(type):
    """the settings of the music player that the android class keeps as static fields; they are read from the app each time"""

    def __getattr__(cls, name):
        state = _state()
        if name == "shuffleMusic":
            return bool(state["shuffle"])
        if name == "repeatMode":
            # 0 off, 1 the list, 2 the song, as the android client counts
            return int(state["repeat"])
        raise AttributeError(name)


class SharedConfig(Object, metaclass=_SharedConfigMeta):
    # the app fetches a song it has not got when it starts, which is what streaming does for the plugin
    streamMedia = True
    # the playlist is presented so that the next song is the one before the current, see the top of the module
    playOrderReversed = False


def play_routed(index):
    """a song is about to start in the app: a plugin that hooks playMessage gets to run first. False when none does, and the app starts the song"""
    controller = MediaController.getInstance()
    if not controller._hooked():
        return False
    controller.playMessage(_message_of(_ui.ask("music.entry", index=int(index))))
    return True


def pause_routed():
    """the app is about to pause a song, see play_routed"""
    controller = MediaController.getInstance()
    if not controller._hooked():
        return False
    controller.pauseMessage(controller.getPlayingMessageObject())
    return True


SharedConfig.__module__ = "org.telegram.messenger"
MediaController.__module__ = "org.telegram.messenger"
VideoPlayer.__module__ = "org.telegram.ui.Components"
