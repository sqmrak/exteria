"""keys that are not RSA: elliptic curve (P-256, P-384, P-521), Diffie-Hellman (the rfc 3526 groups and groups of a program) and X25519 and
X448, with the specs, the generation, the encodings, javax.crypto.KeyAgreement (ECDH, DH, X25519, X448, XDH) and ECDSA signing

KeyPairGenerator, KeyFactory and Signature in jcrypto hand these algorithms to this module by name. the arithmetic is python integers: a
P-256 multiplication takes a few milliseconds on a computer, P-521 and DH 4096 ten times that"""

import hashlib
import hmac as _hmac
import os

from . import runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jcert import (_CURVE_PARAMETERS, _CURVES, DerError, ECPublicKeyImpl, GenericPublicKey, _cert_public_key, _ec_add,
                    _ec_multiply, der_children, der_encode, der_int, der_oid, der_oid_encode, der_read, ecdsa_verify)
from .jcrypto import _EncodedSpec, _array, _bytes, _throw
from .jlang import Object
from .jnum import BigInteger
from .jutil import check_nonnull

_SPEC = ("java.security.spec.KeySpec",)
_PARAM = ("java.security.spec.AlgorithmParameterSpec",)


def _define_interfaces(table):
    for line in table.strip().splitlines():
        name, *parents = line.split()
        host_class(name, interface=True, interfaces=tuple(parents))(type(name.rsplit(".", 1)[1], (), {"__slots__": ()}))


_define_interfaces("""
java.security.interfaces.XECKey
java.security.interfaces.XECPublicKey java.security.PublicKey java.security.interfaces.XECKey
java.security.interfaces.XECPrivateKey java.security.PrivateKey java.security.interfaces.XECKey
javax.crypto.interfaces.DHKey
javax.crypto.interfaces.DHPublicKey java.security.PublicKey javax.crypto.interfaces.DHKey
javax.crypto.interfaces.DHPrivateKey java.security.PrivateKey javax.crypto.interfaces.DHKey
""")


def _int(value):
    return value._v if isinstance(value, BigInteger) else value


def _der_int(n):
    return der_encode(0x02, n.to_bytes((n.bit_length() + 8) // 8, "big", signed=True))


def _oid(text):
    return der_encode(0x06, der_oid_encode(text))


def _seq(*parts):
    return der_encode(0x30, b"".join(parts))


_CURVE_ALIASES = {
    "secp256r1": "secp256r1", "nist p-256": "secp256r1", "p-256": "secp256r1", "prime256v1": "secp256r1", "1.2.840.10045.3.1.7": "secp256r1",
    "secp384r1": "secp384r1", "nist p-384": "secp384r1", "p-384": "secp384r1", "1.3.132.0.34": "secp384r1",
    "secp521r1": "secp521r1", "nist p-521": "secp521r1", "p-521": "secp521r1", "1.3.132.0.35": "secp521r1",
}
_OID_OF = {value[0]: oid for oid, value in _CURVES.items()}
_EC_OID = "1.2.840.10045.2.1"
_CURVE_BITS = {256: "secp256r1", 384: "secp384r1", 521: "secp521r1"}


def curve_name(name):
    found = _CURVE_ALIASES.get(str(name).lower())
    if found is None:
        _throw("java.security.InvalidAlgorithmParameterException", "Unknown curve name: %s" % name)
    return found


def ec_param_spec(name):
    p, a, b, gx, gy, n, h = _CURVE_PARAMETERS[name]
    field = lookup_host("java.security.spec.ECFieldFp").py(BigInteger(p))
    curve = lookup_host("java.security.spec.EllipticCurve").py(field, BigInteger(a), BigInteger(b))
    point = lookup_host("java.security.spec.ECPoint").py(BigInteger(gx), BigInteger(gy))
    return lookup_host("java.security.spec.ECParameterSpec").py(curve, point, BigInteger(n), h)


def curve_of_spec(spec):
    """the name of the curve an ECParameterSpec describes"""
    curve = spec.getCurve()
    for name, (cp, ca, cb, gx, gy, n, h) in _CURVE_PARAMETERS.items():
        if _int(spec.getOrder()) == n and _int(curve.getA()) == ca and _int(curve.getB()) == cb and \
                _int(spec.getGenerator().getAffineX()) == gx and _int(spec.getGenerator().getAffineY()) == gy:
            return name
    _throw("java.security.InvalidKeyException", "Unsupported curve")


def _on_curve(name, point):
    p, a, b = _CURVE_PARAMETERS[name][:3]
    x, y = point
    return 0 <= x < p and 0 <= y < p and (y * y - (x * x * x + a * x + b)) % p == 0


def _ec_public_encoding(name, point):
    size = (_CURVE_PARAMETERS[name][0].bit_length() + 7) // 8
    raw = b"\x04" + point[0].to_bytes(size, "big") + point[1].to_bytes(size, "big")
    return _seq(_seq(_oid(_EC_OID), _oid(_OID_OF[name])), der_encode(0x03, b"\x00" + raw))


class ECPrivateKeyImpl(Object):
    def __init__(self, name, s, raw=None):
        self._name, self._s, self._raw = name, s, raw

    def getAlgorithm(self):
        return "EC"

    def getFormat(self):
        return "PKCS#8"

    def getS(self):
        return BigInteger(self._s)

    def getParams(self):
        return ec_param_spec(self._name)

    def getEncoded(self):
        if self._raw is not None:
            return _array(self._raw)
        size = (_CURVE_PARAMETERS[self._name][5].bit_length() + 7) // 8
        inner = _seq(_der_int(1), der_encode(0x04, self._s.to_bytes(size, "big")))
        return _array(_seq(_der_int(0), _seq(_oid(_EC_OID), _oid(_OID_OF[self._name])), der_encode(0x04, inner)))

    def equals(self, other):
        return 1 if isinstance(other, ECPrivateKeyImpl) and (other._name, other._s) == (self._name, self._s) else 0

    def hashCode(self):
        return runtime.wrap32(self._s)

    def destroy(self):
        pass

    def isDestroyed(self):
        return 0


host_class("sun.security.ec.ECPrivateKeyImpl", interfaces=("java.security.interfaces.ECPrivateKey",))(ECPrivateKeyImpl)


def ec_public(name, point):
    return _cert_public_key(_ec_public_encoding(name, point))


def ec_generate(name):
    p, a, b, gx, gy, n, h = _CURVE_PARAMETERS[name]
    while True:
        s = int.from_bytes(os.urandom((n.bit_length() + 7) // 8 + 8), "big") % (n - 1) + 1
        if 0 < s < n:
            break
    return ec_public(name, _ec_multiply(_CURVE_PARAMETERS[name], s, (gx, gy))), ECPrivateKeyImpl(name, s)


def _ec_point_of_key(key):
    return key._x, key._y


def _ec_name_of_key(key):
    return _CURVES[key._curve_oid][0]


def ecdh(private, public):
    name = private._name
    if not isinstance(public, ECPublicKeyImpl) or _ec_name_of_key(public) != name:
        _throw("java.security.InvalidKeyException", "Public key is not on the same curve")
    point = _ec_point_of_key(public)
    if not _on_curve(name, point):
        _throw("java.security.InvalidKeyException", "Public point is not on the curve")
    shared = _ec_multiply(_CURVE_PARAMETERS[name], private._s, point)
    if shared is None:
        _throw("java.security.InvalidKeyException", "Point is at infinity")
    return shared[0].to_bytes((_CURVE_PARAMETERS[name][0].bit_length() + 7) // 8, "big")


# ECDSA

def ecdsa_sign(private, digest):
    name = private._name
    curve = _CURVE_PARAMETERS[name]
    n, gx, gy = curve[5], curve[3], curve[4]
    e = int.from_bytes(digest, "big")
    excess = len(digest) * 8 - n.bit_length()
    if excess > 0:
        e >>= excess
    while True:
        k = int.from_bytes(os.urandom((n.bit_length() + 7) // 8 + 8), "big") % (n - 1) + 1
        point = _ec_multiply(curve, k, (gx, gy))
        r = point[0] % n
        if r == 0:
            continue
        s = pow(k, -1, n) * (e + r * private._s) % n
        if s:
            return _seq(_der_int(r), _der_int(s))


def ecdsa_verify_key(public, digest, signature):
    return ecdsa_verify(_CURVE_PARAMETERS[_ec_name_of_key(public)], _ec_point_of_key(public), digest, signature)


def _pi_scaled(bits):
    """floor(pi * 2**bits) with a few guard bits, by Machin's formula"""
    guard = bits + 32
    one = 1 << guard

    def arctan_inverse(x):
        total = term = one // x
        square = x * x
        k = 1
        while term:
            term //= square
            k += 2
            total += term // k if (k // 2) % 2 == 0 else -(term // k)
        return total
    value = 4 * (4 * arctan_inverse(5) - arctan_inverse(239))
    return value >> 32


_MODP = {1024: 129093, 1536: 741804, 2048: 124476, 3072: 1690314, 4096: 240904, 6144: 929484, 8192: 4743158}
_groups = {}


def modp_group(bits):
    """p and g of the rfc 2409 / 3526 group of that size"""
    if bits not in _groups:
        p = (1 << bits) - (1 << (bits - 64)) - 1 + (1 << 64) * (_pi_scaled(bits - 130) + _MODP[bits])
        _groups[bits] = (p, 2)
    return _groups[bits]


_DH_OID = "1.2.840.113549.1.3.1"
_DH_SIZES = (1024, 1536, 2048, 3072, 4096, 6144, 8192)


def _dh_algorithm(p, g, l):
    params = _der_int(p) + _der_int(g) + (_der_int(l) if l else b"")
    return _seq(_oid(_DH_OID), _seq(params))


class DHPublicKeyImpl(Object):
    def __init__(self, y, p, g, l=0):
        self._y, self._p, self._g, self._l = y, p, g, l

    def getAlgorithm(self):
        return "DH"

    def getFormat(self):
        return "X.509"

    def getY(self):
        return BigInteger(self._y)

    def getParams(self):
        return lookup_host("javax.crypto.spec.DHParameterSpec").py(BigInteger(self._p), BigInteger(self._g), self._l)

    def getEncoded(self):
        return _array(_seq(_dh_algorithm(self._p, self._g, self._l), der_encode(0x03, b"\x00" + _der_int(self._y))))

    def equals(self, other):
        return 1 if isinstance(other, DHPublicKeyImpl) and (other._y, other._p, other._g) == (self._y, self._p, self._g) else 0

    def hashCode(self):
        return runtime.wrap32(self._y ^ self._p)


class DHPrivateKeyImpl(Object):
    def __init__(self, x, p, g, l=0):
        self._x, self._p, self._g, self._l = x, p, g, l

    def getAlgorithm(self):
        return "DH"

    def getFormat(self):
        return "PKCS#8"

    def getX(self):
        return BigInteger(self._x)

    def getParams(self):
        return lookup_host("javax.crypto.spec.DHParameterSpec").py(BigInteger(self._p), BigInteger(self._g), self._l)

    def getEncoded(self):
        return _array(_seq(_der_int(0), _dh_algorithm(self._p, self._g, self._l), der_encode(0x04, _der_int(self._x))))

    def equals(self, other):
        return 1 if isinstance(other, DHPrivateKeyImpl) and (other._x, other._p, other._g) == (self._x, self._p, self._g) else 0

    def hashCode(self):
        return runtime.wrap32(self._x ^ self._p)

    def destroy(self):
        pass

    def isDestroyed(self):
        return 0


host_class("com.sun.crypto.provider.DHPublicKey", interfaces=("javax.crypto.interfaces.DHPublicKey",))(DHPublicKeyImpl)
host_class("com.sun.crypto.provider.DHPrivateKey", interfaces=("javax.crypto.interfaces.DHPrivateKey",))(DHPrivateKeyImpl)


@host_class("javax.crypto.spec.DHParameterSpec", interfaces=_PARAM)
class DHParameterSpec(Object):
    def __init__(self, p, g, l=0):
        self._p, self._g, self._l = _int(check_nonnull(p)), _int(check_nonnull(g)), l

    @jmethod("<init>", "(Ljava/math/BigInteger;Ljava/math/BigInteger;)V")
    @jmethod("<init>", "(Ljava/math/BigInteger;Ljava/math/BigInteger;I)V")
    def _init(self, p, g, l=0):
        DHParameterSpec.__init__(self, p, g, l)

    def getP(self):
        return BigInteger(self._p)

    def getG(self):
        return BigInteger(self._g)

    def getL(self):
        return self._l


@host_class("javax.crypto.spec.DHPublicKeySpec", interfaces=_SPEC)
class DHPublicKeySpec(Object):
    def __init__(self, y, p, g):
        self._y, self._p, self._g = _int(check_nonnull(y)), _int(check_nonnull(p)), _int(check_nonnull(g))

    @jmethod("<init>", "(Ljava/math/BigInteger;Ljava/math/BigInteger;Ljava/math/BigInteger;)V")
    def _init(self, y, p, g):
        DHPublicKeySpec.__init__(self, y, p, g)

    def getY(self):
        return BigInteger(self._y)

    def getP(self):
        return BigInteger(self._p)

    def getG(self):
        return BigInteger(self._g)


@host_class("javax.crypto.spec.DHPrivateKeySpec", interfaces=_SPEC)
class DHPrivateKeySpec(Object):
    def __init__(self, x, p, g):
        self._x, self._p, self._g = _int(check_nonnull(x)), _int(check_nonnull(p)), _int(check_nonnull(g))

    @jmethod("<init>", "(Ljava/math/BigInteger;Ljava/math/BigInteger;Ljava/math/BigInteger;)V")
    def _init(self, x, p, g):
        DHPrivateKeySpec.__init__(self, x, p, g)

    def getX(self):
        return BigInteger(self._x)

    def getP(self):
        return BigInteger(self._p)

    def getG(self):
        return BigInteger(self._g)


def dh_generate(p, g, l=0):
    bits = l if l else min(p.bit_length() - 1, 512)
    while True:
        x = int.from_bytes(os.urandom((bits + 7) // 8), "big") & ((1 << bits) - 1)
        if 1 < x < p - 1:
            break
    return DHPublicKeyImpl(pow(g, x, p), p, g, l), DHPrivateKeyImpl(x, p, g, l)


def dh_agree(private, public):
    if not isinstance(public, DHPublicKeyImpl) or (public._p, public._g) != (private._p, private._g):
        _throw("java.security.InvalidKeyException", "Incompatible parameters")
    p = private._p
    if not 1 < public._y < p - 1:
        _throw("java.security.InvalidKeyException", "Public key is not valid")
    return pow(public._y, private._x, p).to_bytes((p.bit_length() + 7) // 8, "big")


_XDH = {
    "X25519": dict(oid="1.3.101.110", bits=255, size=32, p=2 ** 255 - 19, a24=121665, base=9),
    "X448": dict(oid="1.3.101.111", bits=448, size=56, p=2 ** 448 - 2 ** 224 - 1, a24=39081, base=5),
}


def _clamp(name, scalar):
    k = bytearray(scalar)
    if name == "X25519":
        k[0] &= 248
        k[31] &= 127
        k[31] |= 64
    else:
        k[0] &= 252
        k[55] |= 128
    return int.from_bytes(k, "little")


def x_multiply(name, scalar, u):
    """rfc 7748 section 5: the montgomery ladder"""
    c = _XDH[name]
    p, a24, bits = c["p"], c["a24"], c["bits"]
    k = _clamp(name, scalar)
    x1, x2, z2, x3, z3, swap = u % p, 1, 0, u % p, 1, 0
    for t in range(bits - 1, -1, -1):
        bit = (k >> t) & 1
        swap ^= bit
        if swap:
            x2, x3, z2, z3 = x3, x2, z3, z2
        swap = bit
        a = (x2 + z2) % p
        aa = a * a % p
        b = (x2 - z2) % p
        bb = b * b % p
        e = (aa - bb) % p
        cc = (x3 + z3) % p
        d = (x3 - z3) % p
        da = d * a % p
        cb = cc * b % p
        x3 = (da + cb) ** 2 % p
        z3 = x1 * (da - cb) ** 2 % p
        x2 = aa * bb % p
        z2 = e * (aa + a24 * e) % p
    if swap:
        x2, x3, z2, z3 = x3, x2, z3, z2
    return x2 * pow(z2, p - 2, p) % p


def _decode_u(name, raw):
    value = int.from_bytes(raw, "little")
    if name == "X25519":
        value &= (1 << 255) - 1
    return value


class XDHPublicKeyImpl(Object):
    def __init__(self, name, u):
        self._name, self._u = name, u

    def getAlgorithm(self):
        return "XDH"

    def getFormat(self):
        return "X.509"

    def getU(self):
        return BigInteger(self._u)

    def getParams(self):
        return lookup_host("java.security.spec.NamedParameterSpec").py(self._name)

    def getEncoded(self):
        raw = self._u.to_bytes(_XDH[self._name]["size"], "little")
        return _array(_seq(_seq(_oid(_XDH[self._name]["oid"])), der_encode(0x03, b"\x00" + raw)))

    def equals(self, other):
        return 1 if isinstance(other, XDHPublicKeyImpl) and (other._name, other._u) == (self._name, self._u) else 0

    def hashCode(self):
        return runtime.wrap32(self._u)


class XDHPrivateKeyImpl(Object):
    def __init__(self, name, scalar):
        self._name, self._k = name, bytes(scalar)

    def getAlgorithm(self):
        return "XDH"

    def getFormat(self):
        return "PKCS#8"

    def getScalar(self):
        return lookup_host("java.util.Optional").py.of(_array(self._k))

    def getParams(self):
        return lookup_host("java.security.spec.NamedParameterSpec").py(self._name)

    def getEncoded(self):
        return _array(_seq(_der_int(0), _seq(_oid(_XDH[self._name]["oid"])), der_encode(0x04, der_encode(0x04, self._k))))

    def equals(self, other):
        return 1 if isinstance(other, XDHPrivateKeyImpl) and (other._name, other._k) == (self._name, self._k) else 0

    def hashCode(self):
        return runtime.wrap32(int.from_bytes(self._k[:4], "big"))

    def destroy(self):
        pass

    def isDestroyed(self):
        return 0


host_class("sun.security.ec.XDHPublicKeyImpl", interfaces=("java.security.interfaces.XECPublicKey",))(XDHPublicKeyImpl)
host_class("sun.security.ec.XDHPrivateKeyImpl", interfaces=("java.security.interfaces.XECPrivateKey",))(XDHPrivateKeyImpl)


@host_class("java.security.spec.XECPublicKeySpec", interfaces=_SPEC)
class XECPublicKeySpec(Object):
    def __init__(self, params, u):
        self._params, self._u = check_nonnull(params), _int(check_nonnull(u))

    @jmethod("<init>", "(Ljava/security/spec/AlgorithmParameterSpec;Ljava/math/BigInteger;)V")
    def _init(self, params, u):
        XECPublicKeySpec.__init__(self, params, u)

    def getParams(self):
        return self._params

    def getU(self):
        return BigInteger(self._u)


@host_class("java.security.spec.XECPrivateKeySpec", interfaces=_SPEC)
class XECPrivateKeySpec(Object):
    def __init__(self, params, scalar):
        self._params, self._k = check_nonnull(params), _bytes(check_nonnull(scalar))

    @jmethod("<init>", "(Ljava/security/spec/AlgorithmParameterSpec;[B)V")
    def _init(self, params, scalar):
        XECPrivateKeySpec.__init__(self, params, scalar)

    def getParams(self):
        return self._params

    def getScalar(self):
        return _array(self._k)


def xdh_name(spec_or_name):
    name = spec_or_name if isinstance(spec_or_name, str) else spec_or_name.getName()
    if name.upper() not in ("X25519", "X448"):
        _throw("java.security.InvalidAlgorithmParameterException", "Unsupported named parameter: %s" % name)
    return name.upper()


def xdh_generate(name):
    scalar = os.urandom(_XDH[name]["size"])
    u = x_multiply(name, scalar, _XDH[name]["base"])
    return XDHPublicKeyImpl(name, u), XDHPrivateKeyImpl(name, scalar)


def xdh_agree(private, public):
    if not isinstance(public, XDHPublicKeyImpl) or public._name != private._name:
        _throw("java.security.InvalidKeyException", "Incompatible parameters")
    size = _XDH[private._name]["size"]
    secret = x_multiply(private._name, private._k, public._u).to_bytes(size, "little")
    if not any(secret):
        _throw("java.security.InvalidKeyException", "Point has small order")
    return secret


def public_from_spki(spki):
    """the key object for the DER of a SubjectPublicKeyInfo of any algorithm known here"""
    try:
        tag, cs, ce = der_read(spki, 0, len(spki))
        items = der_children(spki, cs, ce, 1)
        algorithm = der_children(spki, items[0][1], items[0][2], 2)
        oid = der_oid(spki, algorithm[0][1], algorithm[0][2])
        bits = spki[items[1][1] + 1:items[1][2]]
        for name, c in _XDH.items():
            if oid == c["oid"]:
                if len(bits) != c["size"]:
                    break
                return XDHPublicKeyImpl(name, _decode_u(name, bits))
        if oid == _DH_OID:
            params = der_children(spki, algorithm[1][1], algorithm[1][2], 3)
            p, g = der_int(spki, params[0][1], params[0][2]), der_int(spki, params[1][1], params[1][2])
            l = der_int(spki, params[2][1], params[2][2]) if len(params) > 2 else 0
            _, ys, ye = der_read(bits, 0, len(bits))
            return DHPublicKeyImpl(der_int(bits, ys, ye), p, g, l)
        return _cert_public_key(spki)
    except (DerError, IndexError, KeyError):
        pass
    _throw("java.security.spec.InvalidKeySpecException", "Invalid key encoding")


def private_from_pkcs8(data):
    try:
        tag, cs, ce = der_read(data, 0, len(data))
        items = der_children(data, cs, ce, 1)
        algorithm = der_children(data, items[1][1], items[1][2], 2)
        oid = der_oid(data, algorithm[0][1], algorithm[0][2])
        body = data[items[2][1]:items[2][2]]
        if oid == _EC_OID:
            name = _CURVES[der_oid(data, algorithm[1][1], algorithm[1][2])][0]
            _, bs, be = der_read(body, 0, len(body))
            parts = der_children(body, bs, be, 1)
            return ECPrivateKeyImpl(name, int.from_bytes(body[parts[1][1]:parts[1][2]], "big"), bytes(data))
        for name, c in _XDH.items():
            if oid == c["oid"]:
                _, bs, be = der_read(body, 0, len(body))
                return XDHPrivateKeyImpl(name, body[bs:be])
        if oid == _DH_OID:
            params = der_children(data, algorithm[1][1], algorithm[1][2], 3)
            p, g = der_int(data, params[0][1], params[0][2]), der_int(data, params[1][1], params[1][2])
            l = der_int(data, params[2][1], params[2][2]) if len(params) > 2 else 0
            _, xs, xe = der_read(body, 0, len(body))
            return DHPrivateKeyImpl(der_int(body, xs, xe), p, g, l)
    except (DerError, IndexError, KeyError):
        pass
    _throw("java.security.spec.InvalidKeySpecException", "Invalid key encoding")


def key_family(algorithm):
    """ec, dh or xdh for a KeyPairGenerator or KeyFactory algorithm name, else None"""
    name = algorithm.upper()
    if name == "EC":
        return "ec"
    if name in ("DH", "DIFFIEHELLMAN"):
        return "dh"
    if name in ("X25519", "X448", "XDH"):
        return "xdh"
    return None


class Generator:
    """what KeyPairGenerator.initialize and generateKeyPair do for ec, dh and xdh"""

    def __init__(self, family, algorithm):
        self.family = family
        self.curve = "secp256r1"
        self.dh = None
        self.dh_bits = 2048
        self.xdh = algorithm.upper() if algorithm.upper() in _XDH else "X25519"

    def initialize(self, first):
        if isinstance(first, int):
            if self.family == "ec":
                if first not in _CURVE_BITS:
                    _throw("java.security.InvalidParameterException", "Unsupported size: %d" % first)
                self.curve = _CURVE_BITS[first]
            elif self.family == "dh":
                if first < 512 or first > 8192 or (first % 64 and first not in _DH_SIZES):
                    _throw("java.security.InvalidParameterException", "DH key size must be multiple of 64 and range from 512 to 8192 (inclusive). The specific key size %d is not supported" % first)
                self.dh_bits = first
                self.dh = None
            else:
                if first not in (255, 448):
                    _throw("java.security.InvalidParameterException", "Unsupported size")
                self.xdh = "X25519" if first == 255 else "X448"
            return
        if self.family == "ec":
            if first.getClass().getName() == "java.security.spec.ECGenParameterSpec":
                self.curve = curve_name(first.getName())
            else:
                self.curve = curve_of_spec(first)
        elif self.family == "dh":
            if not isinstance(first, DHParameterSpec):
                _throw("java.security.InvalidAlgorithmParameterException", "Inappropriate parameter type")
            self.dh = (first._p, first._g, first._l)
        else:
            self.xdh = xdh_name(first)

    def generate(self):
        if self.family == "ec":
            public, private = ec_generate(self.curve)
        elif self.family == "dh":
            if self.dh is None:
                size = min((s for s in _DH_SIZES if s >= self.dh_bits), default=2048)
                p, g = modp_group(size)
                self.dh = (p, g, 0)
            public, private = dh_generate(*self.dh)
        else:
            public, private = xdh_generate(self.xdh)
        return public, private


def key_spec_public(family, spec):
    if family == "ec" and getattr(spec, "getW", None) is not None and getattr(spec, "getParams", None) is not None:
        name = curve_of_spec(spec.getParams())
        point = spec.getW()
        pt = (_int(point.getAffineX()), _int(point.getAffineY()))
        if not _on_curve(name, pt):
            _throw("java.security.spec.InvalidKeySpecException", "Point is not on the curve")
        return ec_public(name, pt)
    if family == "dh" and isinstance(spec, DHPublicKeySpec):
        return DHPublicKeyImpl(spec._y, spec._p, spec._g)
    if family == "xdh" and isinstance(spec, XECPublicKeySpec):
        name = xdh_name(spec._params)
        return XDHPublicKeyImpl(name, spec._u % _XDH[name]["p"])
    if isinstance(spec, _EncodedSpec):
        key = public_from_spki(spec._d)
        if key_family(key.getAlgorithm()) != family:
            _throw("java.security.spec.InvalidKeySpecException", "Inappropriate key specification")
        return key
    _throw("java.security.spec.InvalidKeySpecException", "Inappropriate key specification")


def key_spec_private(family, spec):
    if family == "ec" and getattr(spec, "getS", None) is not None and getattr(spec, "getParams", None) is not None:
        return ECPrivateKeyImpl(curve_of_spec(spec.getParams()), _int(spec.getS()))
    if family == "dh" and isinstance(spec, DHPrivateKeySpec):
        return DHPrivateKeyImpl(spec._x, spec._p, spec._g)
    if family == "xdh" and isinstance(spec, XECPrivateKeySpec):
        name = xdh_name(spec._params)
        if len(spec._k) != _XDH[name]["size"]:
            _throw("java.security.spec.InvalidKeySpecException", "Invalid key length")
        return XDHPrivateKeyImpl(name, spec._k)
    if isinstance(spec, _EncodedSpec):
        key = private_from_pkcs8(spec._d)
        if key_family(key.getAlgorithm()) != family:
            _throw("java.security.spec.InvalidKeySpecException", "Inappropriate key specification")
        return key
    _throw("java.security.spec.InvalidKeySpecException", "Inappropriate key specification")


@host_class("javax.crypto.KeyAgreement")
class KeyAgreement(Object):
    _FAMILIES = {"ECDH": "ec", "DH": "dh", "DIFFIEHELLMAN": "dh", "X25519": "xdh", "X448": "xdh", "XDH": "xdh"}

    def __init__(self, algorithm, family):
        self._algorithm, self._family, self._private, self._secret = algorithm, family, None, None
        self._phase_done = False

    @jstatic("getInstance", "(Ljava/lang/String;)Ljavax/crypto/KeyAgreement;")
    @jstatic("getInstance", "(Ljava/lang/String;Ljava/lang/String;)Ljavax/crypto/KeyAgreement;")
    def getInstance(algorithm, provider=None):
        family = KeyAgreement._FAMILIES.get(check_nonnull(algorithm).upper())
        if family is None:
            _throw("java.security.NoSuchAlgorithmException", "Algorithm %s not available" % algorithm)
        return KeyAgreement(algorithm, family)

    def getAlgorithm(self):
        return self._algorithm

    @jmethod("init", "(Ljava/security/Key;)V")
    @jmethod("init", "(Ljava/security/Key;Ljava/security/SecureRandom;)V")
    @jmethod("init", "(Ljava/security/Key;Ljava/security/spec/AlgorithmParameterSpec;)V")
    @jmethod("init", "(Ljava/security/Key;Ljava/security/spec/AlgorithmParameterSpec;Ljava/security/SecureRandom;)V")
    def init(self, key, params=None, random=None):
        expected = {"ec": ECPrivateKeyImpl, "dh": DHPrivateKeyImpl, "xdh": XDHPrivateKeyImpl}[self._family]
        if not isinstance(key, expected):
            _throw("java.security.InvalidKeyException", "Unsupported key type" if key is not None else "Key must not be null")
        if self._family == "xdh" and self._algorithm.upper() in _XDH and key._name != self._algorithm.upper():
            _throw("java.security.InvalidKeyException", "Parameters must be %s" % self._algorithm)
        self._private, self._secret, self._phase_done = key, None, False

    @jmethod("doPhase", "(Ljava/security/Key;Z)Ljava/security/Key;")
    def doPhase(self, key, last):
        if self._private is None:
            _throw("java.lang.IllegalStateException", "Not initialized")
        if self._phase_done:
            _throw("java.lang.IllegalStateException", "Phase already executed")
        if not last:
            _throw("java.lang.IllegalStateException", "Only two party agreement supported, lastPhase must be true")
        if self._family == "ec":
            self._secret = ecdh(self._private, key)
        elif self._family == "dh":
            self._secret = dh_agree(self._private, key)
        else:
            self._secret = xdh_agree(self._private, key)
        self._phase_done = True
        return None

    def _take(self):
        if not self._phase_done:
            _throw("java.lang.IllegalStateException", "Key agreement has not been completed yet")
        secret, self._secret, self._phase_done = self._secret, None, False
        return secret

    @jmethod("generateSecret", "()[B")
    @jmethod("generateSecret", "([BI)I")
    @jmethod("generateSecret", "(Ljava/lang/String;)Ljavax/crypto/SecretKey;")
    def generateSecret(self, first=None, offset=0):
        if first is None:
            return _array(self._take())
        if isinstance(first, str):
            secret = self._take()
            wanted = {"DES": 8, "DESEDE": 24, "TRIPLEDES": 24, "AES": 16, "BLOWFISH": 16}.get(first.upper())
            if first.upper() == "TLSPREMASTERSECRET":
                wanted = len(secret)
            if wanted is None:
                _throw("java.security.NoSuchAlgorithmException", "Unsupported secret key algorithm: " + first)
            if wanted > len(secret):
                _throw("java.security.InvalidKeyException", "Key material is too short")
            return lookup_host("javax.crypto.spec.SecretKeySpec").py(_array(secret[:wanted]), first)
        if len(first) - offset < len(self._secret or b"") and self._phase_done:
            _throw("javax.crypto.ShortBufferException", "Output buffer too short")
        secret = self._take()
        for i, byte in enumerate(secret):
            first[offset + i] = byte - 256 if byte > 127 else byte
        return len(secret)
