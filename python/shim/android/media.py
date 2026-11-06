"""android.media: MediaPlayer for a local file, played by the app (AVAudioPlayer). one sound plays at a time, as the app holds one"""

from android import _ui
from java.lang import Object


class AudioManager(Object):
    STREAM_MUSIC = 3
    STREAM_VOICE_CALL = 0


class MediaMetadataRetriever(Object):
    """reads a frame of a video file. the app publishes pictures as stories only, and has no other use for a frame of a video, so a video is refused here
    by name and a plugin that shows a cover catches it as it catches an unreadable file"""

    def setDataSource(self, path):
        raise NotImplementedError("a frame of a video cannot be read here: %r is not a picture" % (path,))

    def getFrameAtTime(self, *_args):
        raise NotImplementedError("a frame of a video cannot be read here")

    def release(self):
        pass


class MediaPlayer(Object):
    def __init__(self):
        self._path = None
        self._duration = 0
        self._released = False

    def setAudioStreamType(self, _stream):
        pass

    def setDataSource(self, path):
        if not isinstance(path, str):
            raise NotImplementedError("only a file path can be a data source here")
        self._path = path

    def prepare(self):
        if self._path is None:
            raise RuntimeError("no data source")
        self._duration = int(_ui.ask("audio.open", path=self._path).get("duration_ms", 0))

    def getDuration(self):
        return self._duration

    def start(self):
        _ui.ask("audio.start")

    def stop(self):
        _ui.ask("audio.stop")

    def release(self):
        if not self._released:
            self._released = True
            _ui.ask("audio.release")
