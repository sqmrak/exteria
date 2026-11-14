"""java.security permissions, the elliptic curve, PSS and RSA-CRT key specs, Destroyable, SNI host names and ServerSocketFactory.
each class does what the jdk class does; tests/fixtures/dex/src/Api4.java prints the same text on a jvm"""

import re

from . import runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jcrypto import RSAPrivateKeySpec
from .jlang import Object, jstr
from .jnum import BigInteger
from .jutil import PyIterator, check_nonnull, iterate

_SPEC = ("java.security.spec.KeySpec",)
_PARAM = ("java.security.spec.AlgorithmParameterSpec",)


def _big(value):
    return value._v if hasattr(value, "_v") else value


@host_class("javax.security.auth.Destroyable", interface=True)
class Destroyable:
    __slots__ = ()

    @jmethod("destroy", "()V")
    def destroy(self):
        runtime.throw_new("javax.security.auth.DestroyFailedException", None)

    @jmethod("isDestroyed", "()Z")
    def isDestroyed(self):
        return 0


@host_class("java.security.Permission", abstract=True, interfaces=("java.security.Guard", "java.io.Serializable"))
class Permission(Object):
    def __init__(self, name=None):
        self._name = name

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init(self, name):
        Permission.__init__(self, name)

    def getName(self):
        return self._name

    def getActions(self):
        return ""

    def checkGuard(self, obj):
        return None

    def newPermissionCollection(self):
        return None

    def toString(self):
        actions = self.getActions()
        return '("%s" "%s"%s)' % (runtime.class_of(self).getName(), self._name, ' "%s"' % actions if actions else "")


class _Wildcard:
    @staticmethod
    def implies_name(mine, theirs):
        if mine == "*" or mine == theirs:
            return True
        return mine.endswith(".*") and theirs.startswith(mine[:-1])


@host_class("java.security.BasicPermission", abstract=True)
class BasicPermission(Permission):
    def __init__(self, name, actions=None):
        if name is None:
            runtime.npe("name can't be null")
        if name == "":
            runtime.throw_new("java.lang.IllegalArgumentException", "name can't be empty")
        Permission.__init__(self, name)

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;)V")
    def _init(self, name, actions=None):
        BasicPermission.__init__(self, name, actions)

    def implies(self, other):
        if other is None or runtime.class_of(other) is not runtime.class_of(self):
            return 0
        return 1 if _Wildcard.implies_name(self._name, other._name) else 0

    def equals(self, other):
        return 1 if other is not None and runtime.class_of(other) is runtime.class_of(self) and other._name == self._name else 0

    def hashCode(self):
        from .jfunc import string_hash
        return string_hash(self._name)


for _name in ("java.security.SecurityPermission", "java.lang.RuntimePermission", "java.lang.reflect.ReflectPermission",
              "java.util.logging.LoggingPermission", "javax.security.auth.AuthPermission", "java.nio.file.LinkPermission",
              "java.io.SerializablePermission", "javax.net.ssl.SSLPermission"):
    host_class(_name)(type(_name.rsplit(".", 1)[1], (BasicPermission,), {"__module__": __name__}))


@host_class("java.security.AllPermission", final=True)
class AllPermission(Permission):
    def __init__(self, name=None, actions=None):
        Permission.__init__(self, "<all permissions>")

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;)V")
    def _init(self, name=None, actions=None):
        AllPermission.__init__(self)

    def implies(self, other):
        return 1 if isinstance(other, Permission) else 0

    def equals(self, other):
        return 1 if isinstance(other, AllPermission) else 0

    def hashCode(self):
        return 1

    def getActions(self):
        return "<all actions>"


_FILE_ORDER = ("read", "write", "execute", "delete", "readlink")


def _canonical(actions, allowed):
    if actions is None:
        runtime.npe("actions can't be null")
    found = []
    for word in re.split(r"\s*,\s*", actions.strip()) if actions.strip() else []:
        lowered = word.lower()
        if lowered not in allowed:
            runtime.throw_new("java.lang.IllegalArgumentException", "invalid permission: " + actions)
        if lowered not in found:
            found.append(lowered)
    return [action for action in allowed if action in found]


@host_class("java.io.FilePermission", final=True)
class FilePermission(Permission):
    def __init__(self, path, actions):
        if path is None:
            runtime.npe("name can't be null")
        Permission.__init__(self, path)
        self._actions = _canonical(actions, _FILE_ORDER)
        if not self._actions and actions.strip() == "":
            runtime.throw_new("java.lang.IllegalArgumentException", "invalid actions mask")

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;)V")
    def _init(self, path, actions):
        FilePermission.__init__(self, path, actions)

    def getActions(self):
        return ",".join(self._actions)

    def _path_implies(self, mine, theirs):
        if mine == "<<ALL FILES>>":
            return True
        if theirs == "<<ALL FILES>>":
            return False
        if mine.endswith("/-") or mine.endswith("\\-"):
            return theirs.startswith(mine[:-1]) and len(theirs) >= len(mine) - 1 and theirs != mine[:-2] or theirs == mine
        if mine.endswith("/*"):
            rest = theirs[len(mine) - 1:] if theirs.startswith(mine[:-1]) else None
            return rest is not None and rest != "" and "/" not in rest.rstrip("/") or theirs == mine
        return mine == theirs

    def implies(self, other):
        if not isinstance(other, FilePermission):
            return 0
        return 1 if set(other._actions) <= set(self._actions) and self._path_implies(self._name, other._name) else 0

    def equals(self, other):
        return 1 if isinstance(other, FilePermission) and other._name == self._name and other._actions == self._actions else 0

    def hashCode(self):
        from .jfunc import string_hash
        return string_hash(self._name)


@host_class("java.util.PropertyPermission", final=True)
class PropertyPermission(BasicPermission):
    def __init__(self, name, actions):
        BasicPermission.__init__(self, name)
        self._actions = _canonical(actions, ("read", "write"))

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;)V")
    def _init_actions(self, name, actions):
        PropertyPermission.__init__(self, name, actions)

    def getActions(self):
        return ",".join(self._actions)

    def implies(self, other):
        if not isinstance(other, PropertyPermission):
            return 0
        return 1 if set(other._actions) <= set(self._actions) and _Wildcard.implies_name(self._name, other._name) else 0

    def equals(self, other):
        return 1 if isinstance(other, PropertyPermission) and other._name == self._name and other._actions == self._actions else 0


@host_class("java.security.PermissionCollection", abstract=True, interfaces=("java.io.Serializable",))
class PermissionCollection(Object):
    def __init__(self):
        self._items = []
        self._readonly = False

    @jmethod("<init>", "()V")
    def _init(self):
        PermissionCollection.__init__(self)

    def add(self, permission):
        if self._readonly:
            runtime.throw_new("java.lang.SecurityException", "attempt to add a Permission to a readonly PermissionCollection")
        if not isinstance(permission, Permission):
            runtime.throw_new("java.lang.IllegalArgumentException", "invalid permission: " + str(permission))
        self._items.append(permission)

    def implies(self, permission):
        return 1 if any(item.implies(permission) for item in self._items) else 0

    def elements(self):
        return PyIterator(list(self._items))

    def elementsList(self):
        return list(self._items)

    def setReadOnly(self):
        self._readonly = True

    def isReadOnly(self):
        return 1 if self._readonly else 0

    def toString(self):
        return "%s (\n %s\n)" % (runtime.class_of(self).getName(), "\n ".join(item.toString() for item in self._items))


host_class("java.security.Permissions", final=True)(type("Permissions", (PermissionCollection,), {"__module__": __name__}))


@host_class("java.security.spec.ECField", interface=True)
class ECField:
    __slots__ = ()


@host_class("java.security.spec.ECFieldFp", final=True, interfaces=("java.security.spec.ECField",))
class ECFieldFp(Object):
    def __init__(self, p):
        if _big(p) <= 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "p is not positive")
        self._p = _big(p)

    @jmethod("<init>", "(Ljava/math/BigInteger;)V")
    def _init(self, p):
        ECFieldFp.__init__(self, p)

    def getFieldSize(self):
        return self._p.bit_length()

    def getP(self):
        return BigInteger(self._p)

    def equals(self, other):
        return 1 if isinstance(other, ECFieldFp) and other._p == self._p else 0

    def hashCode(self):
        return BigInteger(self._p).hashCode()


@host_class("java.security.spec.ECPoint", final=True)
class ECPoint(Object):
    def __init__(self, x=None, y=None):
        if x is None and y is None:
            self._x = self._y = None
        else:
            self._x, self._y = _big(check_nonnull(x)), _big(check_nonnull(y))

    @jmethod("<init>", "(Ljava/math/BigInteger;Ljava/math/BigInteger;)V")
    def _init(self, x, y):
        ECPoint.__init__(self, x, y)

    def getAffineX(self):
        return None if self._x is None else BigInteger(self._x)

    def getAffineY(self):
        return None if self._y is None else BigInteger(self._y)

    def equals(self, other):
        return 1 if isinstance(other, ECPoint) and (other._x, other._y) == (self._x, self._y) else 0

    def hashCode(self):
        if self._x is None:
            return 0
        return runtime.wrap32(31 * BigInteger(self._x).hashCode() + BigInteger(self._y).hashCode())


ECPoint.POINT_INFINITY = ECPoint()


@host_class("java.security.spec.EllipticCurve", final=True)
class EllipticCurve(Object):
    def __init__(self, field, a, b, seed=None):
        self._field, self._a, self._b = check_nonnull(field), _big(check_nonnull(a)), _big(check_nonnull(b))
        self._seed = seed
        if isinstance(field, ECFieldFp):
            for number, value in (("first", self._a), ("second", self._b)):
                if value < 0:
                    runtime.throw_new("java.lang.IllegalArgumentException", "%s coefficient is negative" % number)
            for number, value in (("first", self._a), ("second", self._b)):
                if value >= field._p:
                    runtime.throw_new("java.lang.IllegalArgumentException", "%s coefficient is too large" % number)

    @jmethod("<init>", "(Ljava/security/spec/ECField;Ljava/math/BigInteger;Ljava/math/BigInteger;)V")
    @jmethod("<init>", "(Ljava/security/spec/ECField;Ljava/math/BigInteger;Ljava/math/BigInteger;[B)V")
    def _init(self, field, a, b, seed=None):
        EllipticCurve.__init__(self, field, a, b, seed)

    def getField(self):
        return self._field

    def getA(self):
        return BigInteger(self._a)

    def getB(self):
        return BigInteger(self._b)

    def getSeed(self):
        return self._seed

    def equals(self, other):
        return 1 if isinstance(other, EllipticCurve) and self._field.equals(other._field) and \
            (self._a, self._b) == (other._a, other._b) else 0

    def hashCode(self):
        return runtime.wrap32(self._field.hashCode() << 6 + BigInteger(self._a).hashCode() << 4 + BigInteger(self._b).hashCode() << 2)


@host_class("java.security.spec.ECParameterSpec", interfaces=_PARAM)
class ECParameterSpec(Object):
    def __init__(self, curve, g, n, h):
        if _big(n) <= 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "n is not positive")
        if h <= 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "h is not positive")
        self._curve, self._g, self._n, self._h = check_nonnull(curve), check_nonnull(g), _big(n), h

    @jmethod("<init>", "(Ljava/security/spec/EllipticCurve;Ljava/security/spec/ECPoint;Ljava/math/BigInteger;I)V")
    def _init(self, curve, g, n, h):
        ECParameterSpec.__init__(self, curve, g, n, h)

    def getCurve(self):
        return self._curve

    def getGenerator(self):
        return self._g

    def getOrder(self):
        return BigInteger(self._n)

    def getCofactor(self):
        return self._h


@host_class("java.security.spec.ECGenParameterSpec", interfaces=_PARAM)
class ECGenParameterSpec(Object):
    def __init__(self, name):
        self._name = check_nonnull(name)

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init(self, name):
        ECGenParameterSpec.__init__(self, name)

    def getName(self):
        return self._name


@host_class("java.security.spec.ECPublicKeySpec", interfaces=_SPEC)
class ECPublicKeySpec(Object):
    def __init__(self, w, params):
        if w.equals(ECPoint.POINT_INFINITY):
            runtime.throw_new("java.lang.IllegalArgumentException", "w is ECPoint.POINT_INFINITY")
        self._w, self._params = w, check_nonnull(params)

    @jmethod("<init>", "(Ljava/security/spec/ECPoint;Ljava/security/spec/ECParameterSpec;)V")
    def _init(self, w, params):
        ECPublicKeySpec.__init__(self, w, params)

    def getW(self):
        return self._w

    def getParams(self):
        return self._params


@host_class("java.security.spec.ECPrivateKeySpec", interfaces=_SPEC)
class ECPrivateKeySpec(Object):
    def __init__(self, s, params):
        self._s, self._params = _big(check_nonnull(s)), check_nonnull(params)

    @jmethod("<init>", "(Ljava/math/BigInteger;Ljava/security/spec/ECParameterSpec;)V")
    def _init(self, s, params):
        ECPrivateKeySpec.__init__(self, s, params)

    def getS(self):
        return BigInteger(self._s)

    def getParams(self):
        return self._params


@host_class("java.security.spec.MGF1ParameterSpec", interfaces=_PARAM)
class MGF1ParameterSpec(Object):
    def __init__(self, algorithm):
        self._algorithm = check_nonnull(algorithm)

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init(self, algorithm):
        MGF1ParameterSpec.__init__(self, algorithm)

    def getDigestAlgorithm(self):
        return self._algorithm


for _field, _algorithm in (("SHA1", "SHA-1"), ("SHA224", "SHA-224"), ("SHA256", "SHA-256"), ("SHA384", "SHA-384"),
                           ("SHA512", "SHA-512"), ("SHA512_224", "SHA-512/224"), ("SHA512_256", "SHA-512/256"),
                           ("SHA3_224", "SHA3-224"), ("SHA3_256", "SHA3-256"), ("SHA3_384", "SHA3-384"), ("SHA3_512", "SHA3-512")):
    setattr(MGF1ParameterSpec, _field, MGF1ParameterSpec(_algorithm))


@host_class("java.security.spec.PSSParameterSpec", interfaces=_PARAM)
class PSSParameterSpec(Object):
    def __init__(self, *args):
        if len(args) == 1:
            self._md, self._mgf, self._mgf_params, self._salt, self._trailer = "SHA-1", "MGF1", MGF1ParameterSpec.SHA1, args[0], 1
        else:
            self._md, self._mgf, self._mgf_params, self._salt, self._trailer = args
        if self._salt < 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "negative saltLen value: %d" % self._salt)
        if self._trailer < 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "negative trailerField: %d" % self._trailer)
        check_nonnull(self._md)
        check_nonnull(self._mgf)

    @jmethod("<init>", "(I)V")
    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/security/spec/AlgorithmParameterSpec;II)V")
    def _init(self, *args):
        PSSParameterSpec.__init__(self, *args)

    def getDigestAlgorithm(self):
        return self._md

    def getMGFAlgorithm(self):
        return self._mgf

    def getMGFParameters(self):
        return self._mgf_params

    def getSaltLength(self):
        return self._salt

    def getTrailerField(self):
        return self._trailer


PSSParameterSpec.DEFAULT = PSSParameterSpec("SHA-1", "MGF1", MGF1ParameterSpec.SHA1, 20, 1)


@host_class("java.security.spec.RSAPrivateCrtKeySpec", interfaces=_SPEC)
class RSAPrivateCrtKeySpec(RSAPrivateKeySpec):
    def __init__(self, n, e, d, p, q, pe, qe, crt):
        RSAPrivateKeySpec.__init__(self, n, d)
        self._e, self._p, self._q = _big(e), _big(p), _big(q)
        self._pe, self._qe, self._crt = _big(pe), _big(qe), _big(crt)

    @jmethod("<init>", "(Ljava/math/BigInteger;Ljava/math/BigInteger;Ljava/math/BigInteger;Ljava/math/BigInteger;"
                       "Ljava/math/BigInteger;Ljava/math/BigInteger;Ljava/math/BigInteger;Ljava/math/BigInteger;)V")
    def _init(self, n, e, d, p, q, pe, qe, crt):
        RSAPrivateCrtKeySpec.__init__(self, n, e, d, p, q, pe, qe, crt)

    def getPublicExponent(self):
        return BigInteger(self._e)

    def getPrimeP(self):
        return BigInteger(self._p)

    def getPrimeQ(self):
        return BigInteger(self._q)

    def getPrimeExponentP(self):
        return BigInteger(self._pe)

    def getPrimeExponentQ(self):
        return BigInteger(self._qe)

    def getCrtCoefficient(self):
        return BigInteger(self._crt)


@host_class("java.security.spec.NamedParameterSpec", interfaces=_PARAM)
class NamedParameterSpec(Object):
    def __init__(self, name):
        self._name = check_nonnull(name)

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init(self, name):
        NamedParameterSpec.__init__(self, name)

    def getName(self):
        return self._name


for _field in ("X25519", "X448", "ED25519", "ED448"):
    setattr(NamedParameterSpec, _field, NamedParameterSpec(_field if _field.startswith("X") else "Ed" + _field[2:]))


@host_class("javax.net.ssl.StandardConstants", final=True)
class StandardConstants(Object):
    SNI_HOST_NAME = 0


@host_class("javax.net.ssl.SNIServerName", abstract=True)
class SNIServerName(Object):
    def __init__(self, type_, encoded):
        if not 0 <= type_ <= 255:
            runtime.throw_new("java.lang.IllegalArgumentException", "Server name type is not in the range of 0 to 255")
        self._type = type_
        self._encoded = bytes(b & 0xFF for b in check_nonnull(encoded))

    @jmethod("<init>", "(I[B)V")
    def _init(self, type_, encoded):
        SNIServerName.__init__(self, type_, encoded)

    def getType(self):
        return self._type

    def getEncoded(self):
        array = runtime.new_array("[B", 0)
        array.extend(b - 256 if b > 127 else b for b in self._encoded)
        return array

    def equals(self, other):
        return 1 if isinstance(other, SNIServerName) and other._type == self._type and other._encoded == self._encoded else 0

    def hashCode(self):
        return runtime.wrap32(31 * (31 * 17 + self._type) + sum(
            (b - 256 if b > 127 else b) * 31 ** (len(self._encoded) - 1 - i) for i, b in enumerate(self._encoded)))

    def toString(self):
        if self._type == 0:
            return "type=host_name (0), value=" + ":".join("%02X" % b for b in self._encoded)
        return "type=(%d), value=%s" % (self._type, ":".join("%02X" % b for b in self._encoded))


@host_class("javax.net.ssl.SNIHostName")
class SNIHostName(SNIServerName):
    def __init__(self, hostname):
        if isinstance(hostname, str):
            name = hostname
            data = name.encode("ascii", "strict") if name.isascii() else name.encode("idna")
        else:
            data = bytes(b & 0xFF for b in check_nonnull(hostname))
            name = data.decode("ascii")
        if not name or name.endswith("."):
            runtime.throw_new("java.lang.IllegalArgumentException", "Server name value of host_name cannot be empty"
                              if not name else "Server name value of host_name cannot have the trailing dot")
        SNIServerName.__init__(self, 0, list(data))
        self._host = data.decode("ascii")

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "([B)V")
    def _init_host(self, hostname):
        SNIHostName.__init__(self, hostname)

    def getAsciiName(self):
        return self._host

    def equals(self, other):
        return 1 if isinstance(other, SNIHostName) and other._host.lower() == self._host.lower() else 0

    def hashCode(self):
        from .jfunc import string_hash
        return string_hash(self._host.upper())

    def toString(self):
        return "type=host_name (0), value=" + self._host

    @staticmethod
    def createSNIMatcher(regex):
        return _HostNameMatcher(check_nonnull(regex))


@host_class("javax.net.ssl.SNIMatcher", abstract=True)
class SNIMatcher(Object):
    def __init__(self, type_):
        self._type = type_

    @jmethod("<init>", "(I)V")
    def _init(self, type_):
        SNIMatcher.__init__(self, type_)

    def getType(self):
        return self._type


class _HostNameMatcher(SNIMatcher):
    def __init__(self, regex):
        SNIMatcher.__init__(self, 0)
        from .jtext import Pattern
        self._pattern = Pattern(regex, Pattern.CASE_INSENSITIVE)

    def matches(self, server_name):
        if server_name is None:
            runtime.throw_new("java.lang.IllegalArgumentException", "The SNIServerName argument cannot be null")
        name = server_name._host if isinstance(server_name, SNIHostName) else server_name._encoded.decode("ascii", "replace")
        return 1 if self._pattern._re.fullmatch(name) else 0


@host_class("javax.net.ServerSocketFactory", abstract=True)
class ServerSocketFactory(Object):
    _default = None

    @jmethod("<init>", "()V")
    def _init(self):
        return None

    @jstatic("getDefault", "()Ljavax/net/ServerSocketFactory;")
    def getDefault():
        if ServerSocketFactory._default is None:
            ServerSocketFactory._default = DefaultServerSocketFactory()
        return ServerSocketFactory._default


@host_class("javax.net.DefaultServerSocketFactory")
class DefaultServerSocketFactory(ServerSocketFactory):
    def createServerSocket(self, *args):
        return lookup_host("java.net.ServerSocket").py(*args)
