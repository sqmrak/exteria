"""android.content.pm: the version a plugin reads to decide whether the client is new enough for it"""

from java.lang import Object

# the exteraGram version whose plugin api the shims follow. plugins compare it with their __min_version__ (music_tab asks for 13.1.1, message_cleaner for
# 12.10.6) and stay inactive below it. it is the highest __min_version__ of the plugins the shims were built and run against, not a claim of the whole api: move it
# only after the api a newer plugin needs is there. the version of the app itself stays BuildVars.BUILD_VERSION_STRING
EXTERAGRAM_API = "13.1.1"


class PackageInfo(Object):
    def __init__(self, package_name):
        self.packageName = package_name
        self.versionName = EXTERAGRAM_API
        self.versionCode = 0


class PackageManager(Object):
    class NameNotFoundException(Exception):
        pass

    def __init__(self, package_name):
        self._package = package_name

    def getPackageInfo(self, package_name, _flags=0):
        """the package of the app answers; any other is not installed here"""
        if str(package_name) != self._package:
            raise PackageManager.NameNotFoundException(str(package_name))
        return PackageInfo(self._package)
