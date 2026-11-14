"""android.net.nsd: service discovery. NsdServiceInfo is the record of a service; NsdManager needs the Bonjour browser of the system, which the app does
not give to plugins, so it answers NotImplementedError"""

from java.lang import NullPointerException, Object


class NsdServiceInfo(Object):
    def __init__(self):
        self._name = None
        self._type = None
        self._port = 0
        self._host = None
        self._attributes = {}

    def setServiceName(self, name):
        self._name = None if name is None else str(name)

    def getServiceName(self):
        return self._name

    def setServiceType(self, service_type):
        self._type = None if service_type is None else str(service_type)

    def getServiceType(self):
        return self._type

    def setPort(self, port):
        self._port = int(port)

    def getPort(self):
        return self._port

    def setHost(self, host):
        self._host = host

    def getHost(self):
        return self._host

    def setAttribute(self, key, value=None):
        if key is None:
            raise NullPointerException("key == null")
        self._attributes[str(key)] = None if value is None else str(value)

    def getAttributes(self):
        return dict(self._attributes)

    def toString(self):
        return "name: %s, type: %s, host: %s, port: %d" % (self._name, self._type, self._host, self._port)


class NsdManager(Object):
    PROTOCOL_DNS_SD = 1

    class DiscoveryListener:
        """a program implements onDiscoveryStarted, onDiscoveryStopped, onServiceFound, onServiceLost, onStartDiscoveryFailed and onStopDiscoveryFailed"""

    class ResolveListener:
        """a program implements onServiceResolved(info) and onResolveFailed(info, error)"""

    class RegistrationListener:
        """a program implements onServiceRegistered, onServiceUnregistered, onRegistrationFailed and onUnregistrationFailed"""

    _instance = None

    @staticmethod
    def _get():
        if NsdManager._instance is None:
            NsdManager._instance = NsdManager()
        return NsdManager._instance

    def _unavailable(self, *_arguments):
        raise NotImplementedError("service discovery needs the Bonjour browser of the system, which the app does not give to plugins")

    discoverServices = stopServiceDiscovery = resolveService = registerService = unregisterService = _unavailable
