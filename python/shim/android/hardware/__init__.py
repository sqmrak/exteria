"""android.hardware: the accelerometer, fed by the app"""

from android import _ui
from java.lang import Object


class Sensor(Object):
    TYPE_ACCELEROMETER = 1

    def __init__(self, kind):
        self._kind = kind

    def getType(self):
        return self._kind


class SensorEvent(Object):
    def __init__(self, sensor, values, timestamp):
        self.sensor = sensor
        self.values = values
        self.timestamp = timestamp
        self.accuracy = 3


class SensorEventListener:
    """the interface a plugin implements: onSensorChanged(event) and onAccuracyChanged(sensor, accuracy)"""


class SensorManager(Object):
    SENSOR_DELAY_FASTEST = 0
    SENSOR_DELAY_GAME = 1
    SENSOR_DELAY_UI = 2
    SENSOR_DELAY_NORMAL = 3
    _instance = None

    @staticmethod
    def instance():
        if SensorManager._instance is None:
            SensorManager._instance = SensorManager()
        return SensorManager._instance

    def __init__(self):
        self._listeners = []
        self._accelerometer = Sensor(Sensor.TYPE_ACCELEROMETER)

    def getDefaultSensor(self, kind):
        if kind == Sensor.TYPE_ACCELEROMETER and _ui.ask("sensor.available").get("value"):
            return self._accelerometer
        return None

    def registerListener(self, listener, sensor, rate=SENSOR_DELAY_NORMAL, *_ignored):
        if sensor is not self._accelerometer:
            return False
        if not any(entry is listener for entry in self._listeners):
            self._listeners.append(listener)
        if len(self._listeners) == 1:
            _ui.ask("sensor.start", rate=int(rate))
        return True

    def unregisterListener(self, listener, *_ignored):
        self._listeners = [entry for entry in self._listeners if entry is not listener]
        if not self._listeners:
            _ui.ask("sensor.stop")

    def _deliver(self, x, y, z, timestamp):
        event = SensorEvent(self._accelerometer, [x, y, z], timestamp)
        for listener in list(self._listeners):
            listener.onSensorChanged(event)
